"""
Cookie 自动生成服务 - 使用 Playwright 无头浏览器访问平台并导出 Cookie。
解决抖音等平台需要 JS 生成 Cookie（如 ttwid）才能解析的问题。
"""

import asyncio
import logging
import time
from http.cookiejar import Cookie, MozillaCookieJar
from pathlib import Path

from playwright.async_api import async_playwright

from app.services.ytdlp_service import COOKIES_DIR

logger = logging.getLogger(__name__)

# 平台 → 需要访问的 URL（用于触发 Cookie 生成）
PLATFORM_URLS = {
    "douyin": "https://www.douyin.com",
    "kuaishou": "https://www.kuaishou.com",
    "xiaohongshu": "https://www.xiaohongshu.com",
    "bilibili": "https://www.bilibili.com",
    "weibo": "https://weibo.com",
}

# Cookie 有效期（秒），超过后自动刷新
COOKIE_MAX_AGE = 3600 * 12  # 12 小时


def _cookie_file_path(platform: str) -> Path:
    return COOKIES_DIR / f"{platform}.txt"


def is_cookie_fresh(platform: str) -> bool:
    """检查平台 Cookie 是否存在且未过期"""
    path = _cookie_file_path(platform)
    if not path.exists():
        return False
    age = time.time() - path.stat().st_mtime
    return age < COOKIE_MAX_AGE


def _save_cookies_netscape(cookies: list[dict], platform: str) -> Path:
    """将 Playwright 格式的 Cookie 保存为 Netscape cookies.txt"""
    COOKIES_DIR.mkdir(parents=True, exist_ok=True)
    path = _cookie_file_path(platform)

    jar = MozillaCookieJar(str(path))
    for c in cookies:
        domain = c.get("domain", "")
        if domain and not domain.startswith("."):
            domain = f".{domain}"

        expires = c.get("expires", -1)
        cookie = Cookie(
            version=0,
            name=c["name"],
            value=c["value"],
            port=None,
            port_specified=False,
            domain=domain,
            domain_specified=True,
            domain_initial_dot=domain.startswith("."),
            path=c.get("path", "/"),
            path_specified=True,
            secure=c.get("secure", False),
            expires=int(expires) if expires and expires > 0 else None,
            discard=False,
            comment=None,
            comment_url=None,
            rest={},
        )
        jar.set_cookie(cookie)

    jar.save(ignore_discard=True, ignore_expires=True)
    logger.info("已保存 %d 条 Cookie → %s", len(cookies), path)
    return path


async def generate_cookies(platform: str) -> Path:
    """
    使用系统 Chrome（headless new 模式）访问平台首页，
    等待 JS 执行完毕后导出 Cookie。
    使用真实 Chrome 而非 Playwright 自带的 headless shell，避免被反爬检测。
    """
    url = PLATFORM_URLS.get(platform)
    if not url:
        raise ValueError(f"不支持的平台: {platform}")

    logger.info("正在为 %s 生成 Cookie（系统 Chrome）...", platform)

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            channel="chrome",  # 使用系统安装的真实 Chrome
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-blink-features=AutomationControlled",
                "--disable-infobars",
                "--disable-dev-shm-usage",
                "--window-size=1920,1080",
            ],
        )
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
            ),
            locale="zh-CN",
            viewport={"width": 1920, "height": 1080},
            java_script_enabled=True,
        )

        # 注入反检测脚本：隐藏 webdriver 标志
        await context.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
            Object.defineProperty(navigator, 'plugins', {get: () => [1, 2, 3]});
            Object.defineProperty(navigator, 'languages', {get: () => ['zh-CN', 'zh', 'en']});
            window.chrome = { runtime: {} };
        """)

        page = await context.new_page()

        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=20000)
            # 等待 JS 生成 Cookie（ttwid 等）
            await page.wait_for_timeout(4000)
        except Exception as e:
            logger.warning("页面加载异常（Cookie 可能已生成）: %s", e)

        cookies = await context.cookies()
        await browser.close()

    if not cookies:
        raise RuntimeError(f"未能从 {platform} 获取任何 Cookie")

    # 过滤只保留目标平台的 Cookie
    platform_domains = {platform, f".{platform}.com", f"www.{platform}.com"}
    if platform == "douyin":
        platform_domains.update({".bytedance.com", "bytedance.com"})

    relevant = [
        c for c in cookies
        if any(d in c.get("domain", "") for d in platform_domains)
    ]

    if not relevant:
        relevant = cookies

    return _save_cookies_netscape(relevant, platform)


async def ensure_cookies(platform: str) -> Path | None:
    """
    确保平台有可用的新鲜 Cookie。
    如果已有且未过期则直接返回，否则自动生成。
    """
    if is_cookie_fresh(platform):
        return _cookie_file_path(platform)

    try:
        return await generate_cookies(platform)
    except Exception as e:
        logger.error("为 %s 生成 Cookie 失败: %s", platform, e)
        # 如果有旧的，凑合用
        old = _cookie_file_path(platform)
        if old.exists():
            return old
        return None
