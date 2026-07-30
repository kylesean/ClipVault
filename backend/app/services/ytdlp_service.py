import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from pathlib import Path

import yt_dlp

from app.models.schemas import ParseData, VideoFormat

logger = logging.getLogger(__name__)

# 专用线程池：避免 yt-dlp 同步调用阻塞事件循环
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="ytdlp")

# Cookie 文件目录（Netscape 格式 cookies.txt）
COOKIES_DIR = Path(__file__).parent.parent.parent / "cookies"

# 需要 Cookie 的平台（无 Cookie 会失败）
COOKIE_REQUIRED_PLATFORMS = {"douyin", "kuaishou", "xiaohongshu", "instagram"}

# 平台标识映射
PLATFORM_MAP = {
    "douyin": "douyin",
    "iesdouyin": "douyin",
    "bilibili": "bilibili",
    "kuaishou": "kuaishou",
    "xiaohongshu": "xiaohongshu",
    "youtube": "youtube",
    "instagram": "instagram",
    "weibo": "weibo",
    "weibo.cn": "weibo",
}

# URL 域名 → 平台快速映射（用于在未解析前判断是否需要 Cookie）
URL_PLATFORM_HINTS = {
    "douyin.com": "douyin",
    "iesdouyin.com": "douyin",
    "kuaishou.com": "kuaishou",
    "xiaohongshu.com": "xiaohongshu",
    "xhslink.com": "xiaohongshu",
    "instagram.com": "instagram",
    "instagr.am": "instagram",
}


def _detect_platform(extractor: str) -> str:
    """从 yt-dlp extractor 名称推断平台"""
    extractor_lower = extractor.lower()
    for key, value in PLATFORM_MAP.items():
        if key in extractor_lower:
            return value
    return extractor_lower


def _guess_platform_from_url(url: str) -> str | None:
    """从 URL 域名快速判断平台"""
    url_lower = url.lower()
    for domain, platform in URL_PLATFORM_HINTS.items():
        if domain in url_lower:
            return platform
    return None


def _get_cookie_file(platform: str) -> Path | None:
    """获取平台对应的 Cookie 文件路径（如果存在）"""
    cookie_file = COOKIES_DIR / f"{platform}.txt"
    if cookie_file.exists():
        return cookie_file
    # 通用 fallback
    generic = COOKIES_DIR / "default.txt"
    if generic.exists():
        return generic
    return None


def _build_ydl_opts(cookie_file: Path | None = None) -> dict:
    """构建 yt-dlp 配置"""
    opts: dict = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "nocheckcertificate": True,
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "socket_timeout": 15,
        "retries": 1,
    }
    if cookie_file:
        opts["cookiefile"] = str(cookie_file)
    return opts


def _extract_parse_data(info: dict) -> ParseData:
    """从 yt-dlp info 提取结构化数据"""
    formats: list[VideoFormat] = []
    if "formats" in info and info["formats"]:
        for f in info["formats"]:
            if f.get("url") and f.get("vcodec", "none") != "none":
                height = f.get("height")
                quality = f"{height}p" if height else f.get("format_note", "unknown")
                formats.append(
                    VideoFormat(
                        quality=quality,
                        url=f["url"],
                        size=f.get("filesize") or f.get("filesize_approx"),
                        ext=f.get("ext", "mp4"),
                    )
                )

    if not formats and info.get("url"):
        formats.append(
            VideoFormat(
                quality=f"{info.get('height', '?')}p",
                url=info["url"],
                size=info.get("filesize"),
                ext=info.get("ext", "mp4"),
            )
        )

    # 去重
    seen_urls: set[str] = set()
    unique_formats: list[VideoFormat] = []
    for fmt in formats:
        if fmt.url not in seen_urls:
            seen_urls.add(fmt.url)
            unique_formats.append(fmt)

    return ParseData(
        title=info.get("title", "未知标题"),
        author=info.get("uploader", info.get("channel", "未知作者")),
        platform=_detect_platform(info.get("extractor", "unknown")),
        duration=int(info.get("duration") or 0),
        thumbnail=info.get("thumbnail"),
        formats=unique_formats,
    )


def _parse_video_url_sync(url: str) -> ParseData:
    """
    同步解析逻辑（在线程池中执行）。
    策略：
      1. 已知需要 Cookie 的平台 → 直接带 Cookie 解析
      2. 其他平台 → 先无 Cookie 尝试，失败后自动加载 Cookie 重试
    注意：Cookie 自动生成由异步层（parse_video_url）处理，此处仅读取已有文件。
    """
    platform_hint = _guess_platform_from_url(url)

    # 策略 1：已知需要 Cookie 的平台，直接加载
    if platform_hint in COOKIE_REQUIRED_PLATFORMS:
        cookie_file = _get_cookie_file(platform_hint)
        if cookie_file:
            logger.info("平台 %s 需要 Cookie，使用: %s", platform_hint, cookie_file)
            return _do_parse(url, cookie_file)
        logger.warning("平台 %s 需要 Cookie 但未找到 Cookie 文件", platform_hint)

    # 策略 2：先无 Cookie 尝试
    try:
        return _do_parse(url, None)
    except Exception as e:
        error_msg = str(e).lower()
        if "cookie" in error_msg or "login" in error_msg or "sign in" in error_msg:
            # 尝试用平台 Cookie 或 default Cookie 重试
            platform = platform_hint or "default"
            cookie_file = _get_cookie_file(platform)
            if cookie_file:
                logger.info("无 Cookie 解析失败，使用 %s 重试", cookie_file)
                return _do_parse(url, cookie_file)
        raise


def _do_parse(url: str, cookie_file: Path | None) -> ParseData:
    """执行单次解析"""
    ydl_opts = _build_ydl_opts(cookie_file)

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)

    if info is None:
        raise ValueError("无法解析该链接")

    return _extract_parse_data(info)


async def parse_video_url(url: str) -> ParseData:
    """
    异步入口：
      1. 检测平台是否需要 Cookie，若需要且不存在/过期 → 自动刷新
      2. 将同步解析调度到线程池
    """
    from app.services.cookie_service import ensure_cookies

    # 预判平台是否需要 Cookie
    platform_hint = _guess_platform_from_url(url)
    if platform_hint in COOKIE_REQUIRED_PLATFORMS:
        await ensure_cookies(platform_hint)

    loop = asyncio.get_running_loop()
    try:
        return await loop.run_in_executor(
            _executor, partial(_parse_video_url_sync, url)
        )
    except Exception as e:
        # 如果是 Cookie 错误且平台已知，尝试刷新 Cookie 后重试
        error_msg = str(e).lower()
        if ("cookie" in error_msg or "fresh cookies" in error_msg) and platform_hint:
            refreshed = await _try_refresh_cookies(platform_hint)
            if refreshed:
                return await loop.run_in_executor(
                    _executor, partial(_parse_video_url_sync, url)
                )
        raise


async def _try_refresh_cookies(platform: str) -> bool:
    """
    尝试刷新 Cookie，优先级：
      1. 纯 API 方式（无需浏览器，适合服务器）
      2. Playwright 方式（需要 Chrome，适合本地开发）
    注意：需要登录态的平台（如 Instagram）无法自动刷新，返回 False。
    """
    from app.services.cookie_service import LOGIN_REQUIRED_PLATFORMS

    if platform in LOGIN_REQUIRED_PLATFORMS:
        logger.warning(
            "平台 %s 需要登录态 Cookie，无法自动刷新，请手动上传", platform
        )
        return False

    # 方式 1：纯 API（服务器友好）
    try:
        from app.services.cookie_refresh_service import refresh_douyin_cookie
        logger.info("尝试通过内置 API 刷新 %s Cookie...", platform)
        return await refresh_douyin_cookie()
    except Exception as e:
        logger.warning("API 方式刷新失败: %s", e)

    # 方式 2：Playwright（本地开发用，服务器可能没有 Chrome）
    try:
        from app.services.cookie_service import generate_cookies
        logger.info("尝试通过 Playwright 刷新 %s Cookie...", platform)
        await generate_cookies(platform)
        return True
    except Exception as e:
        logger.warning("Playwright 方式刷新失败（服务器可能未安装 Chrome）: %s", e)

    return False
