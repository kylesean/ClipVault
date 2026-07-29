"""Cookie 管理路由 - 上传/查看/删除/自动生成平台 Cookie 文件"""

from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import PlainTextResponse

from app.services.cookie_service import PLATFORM_URLS, ensure_cookies, generate_cookies
from app.services.ytdlp_service import COOKIES_DIR

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
async def refresh_cookie(platform: str):
    """
    强制刷新指定平台的 Cookie（使用无头浏览器自动生成）。
    支持的平台: douyin, kuaishou, xiaohongshu, bilibili, weibo
    """
    if platform not in PLATFORM_URLS:
        raise HTTPException(
            status_code=400,
            detail=f"不支持自动生成的平台: {platform}，"
                   f"支持: {sorted(PLATFORM_URLS.keys())}",
        )

    try:
        path = await generate_cookies(platform)
        return {
            "message": f"平台 {platform} Cookie 已自动刷新",
            "path": str(path),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cookie 生成失败: {e}")
