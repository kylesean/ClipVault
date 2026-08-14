import logging

from fastapi import APIRouter, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.models.schemas import ParseRequest, ParseResponse
from app.services.cookie_service import LOGIN_REQUIRED_PLATFORMS
from app.services.douyin_scraper import parse_douyin_url
from app.services.url_security import check_target_url
from app.services.ytdlp_service import _guess_platform_from_url, parse_video_url

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api")
limiter = Limiter(key_func=get_remote_address, default_limits=["60/minute"])


def _validated_url(url: str) -> str | None:
    """URL 安全校验，不安全的返回 None（不发起任何外部请求）"""
    try:
        return check_target_url(url)
    except ValueError as e:
        logger.info("解析请求被拒绝（URL 不安全）: %s", e)
        return None


@router.post("/parse", response_model=ParseResponse)
@limiter.limit("20/minute")
async def parse_link(request: Request, req: ParseRequest):
    """
    解析视频链接。
    策略：主引擎（Douyin_TikTok_Download_API）优先 → yt-dlp 兜底。
    主引擎支持：抖音、TikTok、Bilibili（内置签名算法）。
    yt-dlp 兜底：YouTube、快手、小红书、微博等 1800+ 站点。
    """
    if not req.url or not req.url.strip():
        return ParseResponse(code=4000, message="链接不能为空")

    url = req.url.strip()

    # SSRF 防护：仅允许公网 http/https 目标
    safe_url = _validated_url(url)
    if safe_url is None:
        return ParseResponse(code=4001, message="链接无效或不受支持")

    # === 第一层：主引擎（支持抖音/TikTok/B站的专用解析） ===
    try:
        data = await parse_douyin_url(safe_url)
        if data.formats:
            return ParseResponse(code=0, data=data)
    except Exception as e:
        logger.debug("主引擎解析失败，尝试 yt-dlp 兜底: %s", e)

    # === 第二层：yt-dlp 通用引擎兜底 ===
    try:
        data = await parse_video_url(safe_url)
        if not data.formats:
            return ParseResponse(code=4002, message="未找到可用的视频格式")
        return ParseResponse(code=0, data=data)
    except Exception as e:
        error_msg = str(e)
        logger.warning("yt-dlp 解析失败: %s (url=%s)", error_msg[:300], safe_url)
        if "Unsupported URL" in error_msg or "No video" in error_msg:
            return ParseResponse(code=4001, message="链接无效或视频已删除")
        if "timeout" in error_msg.lower():
            return ParseResponse(code=4003, message="解析超时，请重试")
        if "cookie" in error_msg.lower() or "login" in error_msg.lower():
            platform = _guess_platform_from_url(safe_url)
            if platform and platform in LOGIN_REQUIRED_PLATFORMS:
                return ParseResponse(
                    code=4004,
                    message=f"平台 {platform} 需要登录态 Cookie，"
                    f"请先通过浏览器登录 {platform} 后导出 Cookie 并上传到服务端",
                )
            return ParseResponse(code=4004, message="平台 Cookie 已过期，请刷新后重试")
        return ParseResponse(code=5000, message="解析失败，请稍后重试")


@router.get("/health")
@limiter.limit("20/minute")
async def health_check(request: Request):
    """健康检查"""
    return {"status": "ok", "service": "clipvault-parse"}
