import logging

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.models.schemas import ParseRequest, ParseResponse
from app.services.douyin_scraper import parse_douyin_url
from app.services.ytdlp_service import parse_video_url

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api")
limiter = Limiter(key_func=get_remote_address, default_limits=["60/minute"])


@router.post("/parse", response_model=ParseResponse)
@limiter.limit("20/minute")
async def parse_link(request: Request, req: ParseRequest):
    """
    解析视频链接。
    策略：主引擎（Douyin_TikTok_Download_API）优先 → yt-dlp 兆底。
    主引擎支持：抖音、TikTok、Bilibili（内置签名算法）。
    yt-dlp 兆底：YouTube、快手、小红书、微博等 1800+ 站点。
    """
    if not req.url or not req.url.strip():
        return ParseResponse(code=4000, message="链接不能为空")

    url = req.url.strip()

    # === 第一层：主引擎（支持抖音/TikTok/B站的专用解析） ===
    try:
        data = await parse_douyin_url(url)
        if data.formats:
            return ParseResponse(code=0, data=data)
    except Exception as e:
        logger.debug("主引擎解析失败，尝试 yt-dlp 兆底: %s", e)

    # === 第二层：yt-dlp 通用引擎兆底 ===
    try:
        data = await parse_video_url(url)
        if not data.formats:
            return ParseResponse(code=4002, message="未找到可用的视频格式")
        return ParseResponse(code=0, data=data)
    except Exception as e:
        error_msg = str(e)
        if "Unsupported URL" in error_msg or "No video" in error_msg:
            return ParseResponse(code=4001, message="链接无效或视频已删除")
        if "timeout" in error_msg.lower():
            return ParseResponse(code=4003, message="解析超时，请重试")
        if "cookie" in error_msg.lower():
            return ParseResponse(code=4004, message="平台 Cookie 已过期，请刷新后重试")
        return ParseResponse(code=5000, message=f"解析失败: {error_msg}")


@router.get("/health")
async def health_check():
    """健康检查"""
    return {"status": "ok", "service": "clipvault-parse"}
