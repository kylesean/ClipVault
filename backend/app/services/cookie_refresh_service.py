"""
Cookie 自动刷新服务 - 本地生成反爬参数，无需独立解析服务与浏览器。

生成参数：
  - ttwid: 设备标识（调用 ttwid.bytedance.com）
  - s_v_web_id: 访客 ID（本地算法）
  - msToken: 请求令牌（调用 mssdk.bytedance.com，失败用本地伪造值）
  - verify_fp: 设备指纹（本地算法）

生成后统一写入 backend/cookies/douyin.txt（Netscape 格式），
抖音核心爬虫与 yt-dlp 均从此文件读取 Cookie。

刷新策略：
  - 服务启动时立即检查并刷新
  - 之后每 COOKIE_REFRESH_INTERVAL 小时自动刷新
  - 解析失败时触发即时刷新（由 parse 路由/yt-dlp 层调用）
"""

import asyncio
import logging
import os
import time

from app.services.cookie_service import save_browser_cookie_string

logger = logging.getLogger(__name__)

# 刷新间隔（秒），默认 12 小时
COOKIE_REFRESH_INTERVAL = int(os.getenv("COOKIE_REFRESH_INTERVAL", str(12 * 3600)))

# 上次刷新时间
_last_refresh_time: float = 0


async def generate_douyin_cookies() -> str:
    """
    本地生成抖音反爬参数并组装为 Cookie 字符串。
    同时持久化到 backend/cookies/douyin.txt 供爬虫/yt-dlp 使用。
    """
    from app.douyin_core.token_manager import TokenManager, VerifyFpManager

    cookies: dict[str, str] = {}

    # ttwid（失败不影响整体，跳过）
    try:
        ttwid = await asyncio.to_thread(TokenManager.gen_ttwid)
        if ttwid:
            cookies["ttwid"] = ttwid
            logger.debug("生成 ttwid 成功")
    except Exception as e:
        logger.warning("生成 ttwid 失败: %s", e)

    # s_v_web_id（纯本地）
    cookies["s_v_web_id"] = VerifyFpManager.gen_s_v_web_id()
    logger.debug("生成 s_v_web_id 成功")

    # verify_fp（纯本地）
    cookies["verify_fp"] = VerifyFpManager.gen_verify_fp()
    logger.debug("生成 verify_fp 成功")

    # msToken（失败返回本地伪造值）
    ms_token = await asyncio.to_thread(TokenManager.gen_real_msToken)
    if ms_token:
        cookies["msToken"] = ms_token
        logger.debug("生成 msToken 成功")

    if not cookies:
        raise RuntimeError("所有 Cookie 生成均失败")

    # 组装为 Cookie 字符串
    cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())

    # 持久化到 cookies/douyin.txt（Netscape 格式，0600 权限）
    try:
        save_browser_cookie_string("douyin", cookie_str)
    except Exception as e:
        logger.warning("保存 Cookie 文件失败: %s", e)

    logger.info(
        "成功生成 %d 个 Cookie 参数: %s",
        len(cookies),
        list(cookies.keys()),
    )
    return cookie_str


async def refresh_douyin_cookie() -> bool:
    """完整的 Cookie 刷新流程：本地生成 → 持久化"""
    global _last_refresh_time
    try:
        await generate_douyin_cookies()
        _last_refresh_time = time.time()
        return True
    except Exception as e:
        logger.error("Cookie 刷新失败: %s", e)
        return False


async def check_and_refresh() -> None:
    """检查 Cookie 是否过期，过期则自动刷新"""
    elapsed = time.time() - _last_refresh_time
    if elapsed > COOKIE_REFRESH_INTERVAL:
        logger.info("Cookie 已超过 %.1f 小时，执行自动刷新...", elapsed / 3600)
        await refresh_douyin_cookie()


async def start_cookie_scheduler() -> None:
    """
    后台定时任务：
      - 启动时立即刷新一次
      - 之后每 COOKIE_REFRESH_INTERVAL 秒检查并刷新
    """
    logger.info(
        "Cookie 自动刷新调度器启动（间隔: %dh）",
        COOKIE_REFRESH_INTERVAL // 3600,
    )

    # 启动时立即刷新
    await refresh_douyin_cookie()

    # 定时循环
    while True:
        await asyncio.sleep(COOKIE_REFRESH_INTERVAL)
        await check_and_refresh()
