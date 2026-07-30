"""
下载代理 - 解决客户端直接从 CDN 下载时因缺少 Cookie/正确 UA 被拒绝的问题。
后端使用正确的请求头从 CDN 拉取视频，流式转发给客户端。
"""

import logging

import httpx
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api")

# 各平台下载时需要的请求头
_PLATFORM_HEADERS = {
    "douyin": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.douyin.com/",
    },
    "tiktok": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.tiktok.com/",
    },
    "bilibili": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.bilibili.com/",
    },
    "youtube": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        ),
    },
    "instagram": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.instagram.com/",
    },
}

# 默认请求头（无平台匹配时使用）
_DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    ),
}


def _get_headers_for_platform(platform: str) -> dict[str, str]:
    """获取平台对应的下载请求头，包含 Cookie（如果有）"""
    headers = dict(_PLATFORM_HEADERS.get(platform, _DEFAULT_HEADERS))

    # 尝试加载平台 Cookie（用于 TikTok 等需要认证的 CDN）
    from app.services.ytdlp_service import _get_cookie_file

    cookie_file = _get_cookie_file(platform)
    if cookie_file:
        # 读取 Netscape 格式 Cookie 并转为 header 字符串
        cookie_str = _netscape_to_header(cookie_file)
        if cookie_str:
            headers["Cookie"] = cookie_str

    return headers


def _netscape_to_header(cookie_file) -> str:
    """将 Netscape cookies.txt 转为 HTTP Cookie header 字符串"""
    try:
        from http.cookiejar import MozillaCookieJar

        jar = MozillaCookieJar(str(cookie_file))
        jar.load(ignore_discard=True, ignore_expires=True)
        pairs = [f"{c.name}={c.value}" for c in jar]
        return "; ".join(pairs)
    except Exception as e:
        logger.warning("读取 Cookie 文件失败: %s", e)
        return ""


@router.get("/download-proxy")
async def download_proxy(
    url: str = Query(..., description="CDN 视频直链"),
    platform: str = Query("other", description="平台标识"),
):
    """
    流式代理下载：后端用正确的 headers 从 CDN 拉取，转发给客户端。
    解决客户端直接下载被 CDN 拒绝（403）的问题。
    """
    headers = _get_headers_for_platform(platform)

    logger.info("代理下载: platform=%s, url=%s...", platform, url[:80])

    # 使用 httpx 流式请求
    client = httpx.AsyncClient(
        follow_redirects=True,
        timeout=httpx.Timeout(60.0, connect=10.0),
        verify=False,
    )

    try:
        req = client.build_request("GET", url, headers=headers)
        resp = await client.send(req, stream=True)

        if resp.status_code != 200:
            await resp.aclose()
            await client.aclose()
            logger.warning(
                "CDN 返回 %d: platform=%s, url=%s",
                resp.status_code, platform, url[:80],
            )
            raise HTTPException(
                status_code=502,
                detail=f"CDN 返回 {resp.status_code}，下载失败",
            )

        # 获取内容长度（如果有）
        content_length = resp.headers.get("content-length")
        content_type = resp.headers.get("content-type", "video/mp4")

        response_headers = {
            "Content-Type": content_type,
            "Accept-Ranges": "bytes",
        }
        if content_length:
            response_headers["Content-Length"] = content_length

        async def stream_generator():
            try:
                async for chunk in resp.aiter_bytes(chunk_size=64 * 1024):
                    yield chunk
            finally:
                await resp.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_generator(),
            media_type=content_type,
            headers=response_headers,
        )

    except httpx.HTTPError as e:
        await client.aclose()
        logger.error("代理下载网络错误: %s", e)
        raise HTTPException(status_code=502, detail=f"CDN 连接失败: {e}")
