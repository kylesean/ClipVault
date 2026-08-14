"""
下载代理 - 解决客户端直接从 CDN 下载时因缺少 Cookie/正确 UA 被拒绝的问题。
后端使用正确的请求头从 CDN 拉取视频，流式转发给客户端。

安全措施：
  - 仅允许 http/https scheme，且目标 IP 必须是公网地址（防 SSRF）
  - 重定向逐跳复查（防 DNS rebinding / 302 绕过）
  - 单次流式转发字节上限 + 全局并发信号量（防资源耗尽）
  - 按 IP 限流
  - 平台标识白名单（防路径穿越加载任意 Cookie 文件）
  - 日志只记录主机名（不记录含签名 token 的完整 URL）
"""

import asyncio
import logging
import os

import httpx
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import StreamingResponse

from app.routers.parse import limiter
from app.services.url_security import check_target_url, validate_platform

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api")

# 单次代理下载的最大字节数（默认 1GB，可通过环境变量覆盖）
MAX_PROXY_BYTES = int(os.getenv("CLIPVAULT_MAX_PROXY_BYTES", str(1024**3)))

# 全局并发流式转发上限
MAX_CONCURRENT_STREAMS = int(os.getenv("CLIPVAULT_MAX_CONCURRENT_STREAMS", "8"))
_stream_semaphore = asyncio.Semaphore(MAX_CONCURRENT_STREAMS)

# 重定向最大跳数
MAX_REDIRECTS = 5

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

_log_host_cache: dict[str, str] = {}


def _log_host(url: str) -> str:
    """仅返回 scheme://host 用于日志"""
    if url not in _log_host_cache:
        try:
            from urllib.parse import urlparse

            parsed = urlparse(url)
            _log_host_cache[url] = f"{parsed.scheme}://{parsed.hostname}"
        except Exception:
            _log_host_cache[url] = "<invalid>"
    return _log_host_cache[url]


def _get_headers_for_platform(platform: str) -> dict[str, str]:
    """获取平台对应的下载请求头，包含 Cookie（如果有）"""
    headers = dict(_PLATFORM_HEADERS.get(platform, _DEFAULT_HEADERS))

    # 平台标识必须符合白名单，防止路径穿越读取任意文件
    if not validate_platform(platform):
        return headers

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


async def _fetch_with_redirect_guard(
    client: httpx.AsyncClient,
    url: str,
    headers: dict[str, str],
) -> httpx.Response:
    """
    手动处理重定向，每一跳都重新校验目标 URL 安全性。
    返回流式响应（最终 200），调用方负责关闭。
    """
    current_url = url
    for _ in range(MAX_REDIRECTS + 1):
        safe_url = check_target_url(current_url)
        req = client.build_request("GET", safe_url, headers=headers)
        resp = await client.send(req, stream=True)

        if resp.status_code in (301, 302, 303, 307, 308):
            location = resp.headers.get("location")
            await resp.aclose()
            if not location:
                raise HTTPException(status_code=502, detail="CDN 重定向无目标地址")
            from urllib.parse import urljoin

            current_url = urljoin(safe_url, location)
            logger.info("代理重定向: %s -> %s", _log_host(safe_url), _log_host(current_url))
            continue

        return resp

    raise HTTPException(status_code=502, detail="CDN 重定向次数过多")


@router.get("/download-proxy")
@limiter.limit("12/minute")
async def download_proxy(
    request: Request,
    url: str = Query(..., description="CDN 视频直链"),
    platform: str = Query("other", description="平台标识"),
):
    """
    流式代理下载：后端用正确的 headers 从 CDN 拉取，转发给客户端。
    解决客户端直接下载被 CDN 拒绝（403）的问题。
    """
    headers = _get_headers_for_platform(platform)

    # 前置校验（不安全的 URL 直接拒绝，不发起任何请求）
    try:
        check_target_url(url)
    except ValueError as e:
        logger.warning("代理下载被拒绝: %s (client=%s)", e, request.client.host)
        raise HTTPException(status_code=400, detail=str(e))

    logger.info("代理下载: platform=%s, url=%s", platform, _log_host(url))

    if _stream_semaphore.locked():
        raise HTTPException(status_code=429, detail="下载并发过高，请稍后重试")

    async with _stream_semaphore:
        # 使用 httpx 流式请求（验证证书，防中间人）
        client = httpx.AsyncClient(
            follow_redirects=False,
            timeout=httpx.Timeout(60.0, connect=10.0),
            verify=True,
        )

        try:
            resp = await _fetch_with_redirect_guard(client, url, headers)

            if resp.status_code != 200:
                await resp.aclose()
                logger.warning(
                    "CDN 返回 %d: platform=%s, url=%s",
                    resp.status_code, platform, _log_host(url),
                )
                raise HTTPException(
                    status_code=502,
                    detail="CDN 下载失败，请稍后重试",
                )

            # 获取内容长度（如果有）
            content_length = resp.headers.get("content-length")
            content_type = resp.headers.get("content-type", "video/mp4")

            response_headers = {"Content-Type": content_type}
            if content_length:
                try:
                    if int(content_length) > MAX_PROXY_BYTES:
                        logger.warning(
                            "代理下载超过大小限制: %s bytes, url=%s",
                            content_length, _log_host(url),
                        )
                        await resp.aclose()
                        raise HTTPException(status_code=413, detail="文件过大")
                    response_headers["Content-Length"] = content_length
                except ValueError:
                    pass

            async def stream_generator():
                sent = 0
                try:
                    async for chunk in resp.aiter_bytes(chunk_size=64 * 1024):
                        sent += len(chunk)
                        if sent > MAX_PROXY_BYTES:
                            logger.warning(
                                "代理下载超限中断: url=%s", _log_host(url)
                            )
                            return
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
            logger.error("代理下载网络错误: %s (url=%s)", e, _log_host(url))
            raise HTTPException(status_code=502, detail="CDN 连接失败，请稍后重试")
        except HTTPException:
            await client.aclose()
            raise
