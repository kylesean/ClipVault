"""Cookie 管理路由 - 上传/查看/删除/自动生成平台 Cookie 文件"""

import logging
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import PlainTextResponse

from app.models.schemas import CookieRefreshRequest
from app.services.cookie_service import (
    PLATFORM_URLS,
    ensure_cookies,
    generate_cookies,
    save_browser_cookie_string,
)
from app.services.ytdlp_service import COOKIES_DIR

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/cookies", tags=["cookies"])

# 允许的平台白名单
ALLOWED_PLATFORMS = {
    "douyin", "bilibili", "kuaishou",
    "xiaohongshu", "youtube", "weibo", "default",
}


@router.get("")
async def list_cookies():
    """列出已有 Cookie 的平台"""
    COOKIES_DIR.mkdir(parents=True, exist_ok=True)
    files = [f.stem for f in COOKIES_DIR.glob("*.txt")]
    return {"platforms": sorted(files)}


@router.post("/{platform}")
async def upload_cookie(platform: str, file: UploadFile):
    """
    上传指定平台的 Cookie 文件（Netscape cookies.txt 格式）。

    获取方式：
      1. 浏览器安装 "Get cookies.txt LOCALLY" 扩展
      2. 访问对应平台网站（如 douyin.com）
      3. 导出 cookies.txt 并上传
    """
    if platform not in ALLOWED_PLATFORMS:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的平台: {platform}，允许: {sorted(ALLOWED_PLATFORMS)}",
        )

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="文件内容为空")

    COOKIES_DIR.mkdir(parents=True, exist_ok=True)
    target = COOKIES_DIR / f"{platform}.txt"
    target.write_bytes(content)

    return {"message": f"平台 {platform} Cookie 已更新", "size": len(content)}


@router.delete("/{platform}")
async def delete_cookie(platform: str):
    """删除指定平台的 Cookie"""
    target = COOKIES_DIR / f"{platform}.txt"
    if not target.exists():
        raise HTTPException(status_code=404, detail=f"平台 {platform} 无 Cookie 文件")

    target.unlink()
    return {"message": f"平台 {platform} Cookie 已删除"}


@router.get("/{platform}", response_class=PlainTextResponse)
async def get_cookie(platform: str):
    """查看指定平台的 Cookie 内容（调试用）"""
    target = COOKIES_DIR / f"{platform}.txt"
    if not target.exists():
        raise HTTPException(status_code=404, detail=f"平台 {platform} 无 Cookie 文件")

    return target.read_text()


@router.post("/{platform}/refresh")
async def refresh_cookie(platform: str, body: CookieRefreshRequest | None = None):
    """
    刷新指定平台的 Cookie。
    支持三种方式（按优先级）：
      1. 直接传入 Cookie 字符串（浏览器插件/手动提供）
      2. 纯 API 生成（无需浏览器）
      3. Playwright 浏览器生成（需要 Chrome，仅开发环境）
    """
    if platform not in PLATFORM_URLS and platform not in ALLOWED_PLATFORMS:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的平台: {platform}，"
                   f"支持: {sorted(ALLOWED_PLATFORMS)}",
        )

    # 方式 0：直接接收 Cookie 字符串（最优先）
    if body and body.cookie and body.cookie.strip():
        try:
            path = save_browser_cookie_string(platform, body.cookie.strip())
            # 同时注入到 douyin_api 服务
            await _inject_cookie_to_service(platform, body.cookie.strip())
            return {
                "message": f"平台 {platform} Cookie 已直接保存",
                "path": str(path),
            }
        except Exception as e:
            logger.error("直接保存 Cookie 失败: %s", e)
            raise HTTPException(
                status_code=500,
                detail=f"Cookie 保存失败: {e}",
            )

    # 方式 1：纯 API（服务器友好）
    try:
        from app.services.cookie_refresh_service import refresh_douyin_cookie
        success = await refresh_douyin_cookie()
        if success:
            return {"message": f"平台 {platform} Cookie 已通过 API 刷新"}
    except Exception as e:
        logger.warning("API 方式刷新 Cookie 失败: %s", e)

    # 方式 2：Playwright（需要 Chrome，仅开发环境）
    try:
        path = await generate_cookies(platform)
        return {"message": f"平台 {platform} Cookie 已通过浏览器刷新", "path": str(path)}
    except Exception as e:
        logger.warning("Playwright 方式刷新 Cookie 失败: %s", e)

    # 所有方式均失败
    raise HTTPException(
        status_code=500,
        detail=(
            f"Cookie 刷新失败：所有方式均不可用。"
            f"建议：通过请求体直接提供 Cookie 字符串，"
            f"例如: {{\"cookie\": \"your_cookie_string\"}}"
        ),
    )


async def _inject_cookie_to_service(platform: str, cookie_str: str) -> None:
    """将 Cookie 注入到 douyin_api 解析服务（best-effort）"""
    if platform != "douyin":
        return
    try:
        from app.services.cookie_refresh_service import update_service_cookie
        await update_service_cookie(cookie_str)
    except Exception as e:
        logger.warning("Cookie 注入解析服务失败（不影响保存）: %s", e)
