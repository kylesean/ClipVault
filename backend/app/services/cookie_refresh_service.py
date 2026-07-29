"""
Cookie 自动刷新服务 - 无浏览器方案。
调用 Douyin_TikTok_Download_API 内置的生成接口获取反爬参数，
组装为有效 Cookie 并注入服务。适用于无 GUI 的服务器环境。

刷新策略：
  - 服务启动时立即检查并刷新
  - 之后每 COOKIE_REFRESH_INTERVAL 小时自动刷新
  - 解析失败时触发即时刷新（由 parse 路由调用）
"""

import asyncio
import logging
import os
import time

import httpx

logger = logging.getLogger(__name__)

# 抖音解析服务地址
DOUYIN_API_URL = os.getenv("DOUYIN_API_URL", "http://localhost:8080")

# 刷新间隔（秒），默认 12 小时
COOKIE_REFRESH_INTERVAL = int(os.getenv("COOKIE_REFRESH_INTERVAL", str(12 * 3600)))

# 上次刷新时间
_last_refresh_time: float = 0


async def generate_douyin_cookies() -> str:
    """
    调用 Douyin_TikTok_Download_API 内置接口生成关键 Cookie 参数。
    无需浏览器，纯 HTTP 请求即可完成。

    生成的参数：
      - ttwid: 设备标识（必需）
      - s_v_web_id: 访客 ID（必需）
      - msToken: 请求令牌（推荐）
      - verify_fp: 设备指纹（推荐）
    """
    cookies: dict[str, str] = {}

    async with httpx.AsyncClient(
        base_url=DOUYIN_API_URL, timeout=15.0
    ) as client:
        # 生成 ttwid
        try:
            resp = await client.get("/api/douyin/web/generate_ttwid")
            if resp.status_code == 200:
                data = resp.json()
                ttwid = data.get("data", data.get("ttwid", ""))
                if isinstance(ttwid, dict):
                    ttwid = ttwid.get("ttwid", "")
                if ttwid:
                    cookies["ttwid"] = str(ttwid)
                    logger.debug("生成 ttwid 成功")
        except Exception as e:
            logger.warning("生成 ttwid 失败: %s", e)

        # 生成 s_v_web_id
        try:
            resp = await client.get("/api/douyin/web/generate_s_v_web_id")
            if resp.status_code == 200:
                data = resp.json()
                s_v_web_id = data.get("data", data.get("s_v_web_id", ""))
                if isinstance(s_v_web_id, dict):
                    s_v_web_id = s_v_web_id.get("s_v_web_id", "")
                if s_v_web_id:
                    cookies["s_v_web_id"] = str(s_v_web_id)
                    logger.debug("生成 s_v_web_id 成功")
        except Exception as e:
            logger.warning("生成 s_v_web_id 失败: %s", e)

        # 生成 msToken
        try:
            resp = await client.get("/api/douyin/web/generate_real_msToken")
            if resp.status_code == 200:
                data = resp.json()
                ms_token = data.get("data", data.get("msToken", ""))
                if isinstance(ms_token, dict):
                    ms_token = ms_token.get("msToken", "")
                if ms_token:
                    cookies["msToken"] = str(ms_token)
                    logger.debug("生成 msToken 成功")
        except Exception as e:
            logger.warning("生成 msToken 失败: %s", e)

        # 生成 verify_fp
        try:
            resp = await client.get("/api/douyin/web/generate_verify_fp")
            if resp.status_code == 200:
                data = resp.json()
                verify_fp = data.get("data", data.get("verify_fp", ""))
                if isinstance(verify_fp, dict):
                    verify_fp = verify_fp.get("verify_fp", "")
                if verify_fp:
                    cookies["verify_fp"] = str(verify_fp)
                    logger.debug("生成 verify_fp 成功")
        except Exception as e:
            logger.warning("生成 verify_fp 失败: %s", e)

    if not cookies:
        raise RuntimeError("所有 Cookie 生成接口均失败")

    # 组装为 Cookie 字符串
    cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
    logger.info(
        "成功生成 %d 个 Cookie 参数: %s",
        len(cookies),
        list(cookies.keys()),
    )
    return cookie_str


async def update_service_cookie(cookie_str: str) -> bool:
    """将生成的 Cookie 注入到 Douyin_TikTok_Download_API 服务"""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                f"{DOUYIN_API_URL}/api/hybrid/update_cookie",
                json={"service": "douyin", "cookie": cookie_str},
            )
            if resp.status_code == 200:
                logger.info("Cookie 已注入抖音解析服务")
                return True
            logger.warning("Cookie 注入失败: %s %s", resp.status_code, resp.text[:100])
    except Exception as e:
        logger.error("Cookie 注入异常: %s", e)
    return False


async def refresh_douyin_cookie() -> bool:
    """完整的 Cookie 刷新流程：生成 → 注入"""
    global _last_refresh_time
    try:
        cookie_str = await generate_douyin_cookies()
        success = await update_service_cookie(cookie_str)
        if success:
            _last_refresh_time = time.time()
        return success
    except Exception as e:
        logger.error("Cookie 刷新失败: %s", e)
        return False


async def check_and_refresh() -> None:
    """检查 Cookie 是否过期，过期则自动刷新"""
    elapsed = time.time() - _last_refresh_time
    if elapsed > COOKIE_REFRESH_INTERVAL:
        logger.info("Cookie 已超过 %.1f 小时，执行自动刷新...", elapsed / 3600)
        await refresh_douyin_cookie()


async def health_check_parse() -> bool:
    """
    健康检查：用一个已知有效的抖音链接测试解析是否正常。
    如果失败则触发 Cookie 刷新。
    """
    test_url = "https://www.douyin.com/video/7651893932645401704"
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            resp = await client.get(
                f"{DOUYIN_API_URL}/api/hybrid/video_data",
                params={"url": test_url, "minimal": True},
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 200 and data.get("data"):
                    return True

        # 解析失败，尝试刷新 Cookie
        logger.warning("健康检查失败，触发 Cookie 刷新...")
        await refresh_douyin_cookie()
        return False
    except Exception as e:
        logger.error("健康检查异常: %s", e)
        return False


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
