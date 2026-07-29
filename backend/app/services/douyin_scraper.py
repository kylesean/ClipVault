"""
抖音/TikTok 解析客户端 - 调用 Douyin_TikTok_Download_API 服务。
该服务内置 X-Bogus / A-Bogus 签名算法，能正确绕过抖音反爬。
"""

import logging
import os

import httpx

from app.models.schemas import ParseData, VideoFormat

logger = logging.getLogger(__name__)

# Douyin_TikTok_Download_API 服务地址
# Docker 内部通信用 http://douyin-api:80，本地开发用 http://localhost:8080
DOUYIN_API_URL = os.getenv("DOUYIN_API_URL", "http://localhost:8080")


async def parse_douyin_url(url: str) -> ParseData:
    """
    通过 Douyin_TikTok_Download_API 解析抖音/TikTok 链接。
    使用其 /api/hybrid/video_data 端点获取视频信息。
    """
    api_url = f"{DOUYIN_API_URL}/api/hybrid/video_data"

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(api_url, params={"url": url, "minimal": True})

        if resp.status_code != 200:
            raise ValueError(
                f"抖音解析服务返回 {resp.status_code}: {resp.text[:200]}"
            )

        data = resp.json()

    # 适配响应格式
    if data.get("code") != 200:
        msg = data.get("message", "未知错误")
        raise ValueError(f"抖音解析失败: {msg}")

    video_data = data.get("data", {})
    return _extract_parse_data(video_data)


def _extract_parse_data(video_data: dict) -> ParseData:
    """将 Douyin_TikTok_Download_API 的响应转换为我们统一的 ParseData 格式"""

    # 提取视频标题
    title = video_data.get("desc") or "未知标题"

    # 提取作者
    author_info = video_data.get("author", {})
    author = (
        author_info.get("nickname")
        or author_info.get("unique_id")
        or "未知作者"
    )

    # 提取时长（毫秒 → 秒）
    duration_ms = video_data.get("duration", 0)
    duration = int(duration_ms / 1000) if duration_ms > 1000 else int(duration_ms)

    # 提取封面
    thumbnail = None
    cover_data = video_data.get("cover_data", {})
    if isinstance(cover_data, dict):
        # 尝试从 cover_data 中获取
        origin = cover_data.get("origin", {})
        if isinstance(origin, dict):
            url_list = origin.get("url_list", [])
            thumbnail = url_list[0] if url_list else None
    if not thumbnail:
        cover = video_data.get("cover", {})
        if isinstance(cover, dict):
            url_list = cover.get("url_list", [])
            thumbnail = url_list[0] if url_list else None
        elif isinstance(cover, str):
            thumbnail = cover

    # 提取视频下载链接（在 video_data 字段中）
    formats: list[VideoFormat] = []
    vd = video_data.get("video_data", {})

    if isinstance(vd, dict):
        # 高清无水印（优先）
        nwm_hq = vd.get("nwm_video_url_HQ")
        if nwm_hq:
            formats.append(VideoFormat(
                quality="无水印·高清",
                url=nwm_hq,
                size=None,
                ext="mp4",
            ))

        # 普通无水印
        nwm = vd.get("nwm_video_url")
        if nwm:
            formats.append(VideoFormat(
                quality="无水印",
                url=nwm,
                size=None,
                ext="mp4",
            ))

        # 有水印高清（备选）
        wm_hq = vd.get("wm_video_url_HQ")
        if wm_hq:
            formats.append(VideoFormat(
                quality="有水印·高清",
                url=wm_hq,
                size=None,
                ext="mp4",
            ))

    if not formats:
        raise ValueError("未获取到可用的视频下载链接")

    # 判断平台
    platform = video_data.get("platform", "douyin")

    return ParseData(
        title=title,
        author=author,
        platform=platform,
        duration=duration,
        thumbnail=thumbnail,
        formats=formats,
    )


async def health_check() -> bool:
    """检查 Douyin_TikTok_Download_API 服务是否可用"""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{DOUYIN_API_URL}/")
            return resp.status_code == 200
    except Exception:
        return False
