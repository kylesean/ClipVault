# ==============================================================================
# Copyright (C) 2021 Evil0ctal (Douyin_TikTok_Download_API, Apache-2.0)
#
# 本文件是从 https://github.com/Evil0ctal/Douyin_TikTok_Download_API
# 的 crawlers/douyin/web/ 目录精简迁移而来，仅保留 ClipVault 所需的部分。
# 原始文件许可：Apache License 2.0
# ==============================================================================

import os
from pathlib import Path

import yaml

# 本包目录（包含 config.yaml）
PACKAGE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = PACKAGE_DIR / "config.yaml"

# 代理配置（环境变量覆盖，空则走系统代理 trust_env）
DOUYIN_PROXY = os.getenv("DOUYIN_PROXY", "").strip()


def load_config() -> dict:
    """加载抖音 Web 解析配置"""
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


config: dict = load_config()


def get_headers() -> dict:
    """从配置构建请求头（Cookie 从 cookies 目录读取，不在此配置中保存）"""
    douyin_config = config["TokenManager"]["douyin"]
    return {
        "Accept-Language": douyin_config["headers"]["Accept-Language"],
        "User-Agent": douyin_config["headers"]["User-Agent"],
        "Referer": douyin_config["headers"]["Referer"],
        "Cookie": get_cookie_header(),
    }


def get_user_agent() -> str:
    return config["TokenManager"]["douyin"]["headers"]["User-Agent"]


def get_proxies() -> dict | None:
    """返回 httpx 可用的代理配置（仅当环境变量 DOUYIN_PROXY 已设置）"""
    if not DOUYIN_PROXY:
        return None
    return {"http://": DOUYIN_PROXY, "https://": DOUYIN_PROXY}


def get_http_kwargs() -> dict:
    """
    返回兼容 httpx>=0.28 的传输参数：
      - 未配置代理：trust_env=True（走系统 HTTPS_PROXY 等）
      - 配置了代理：显式传入单个 proxy
    """
    if not DOUYIN_PROXY:
        return {"trust_env": True}
    return {"proxy": DOUYIN_PROXY, "trust_env": False}


def get_cookie_header() -> str:
    """
    从 backend/cookies/douyin.txt（Netscape 格式）读取 Cookie 并转为
    "key=value; key2=value2" 请求头字符串。无文件/读取失败返回空串。
    """
    cookie_file = _find_cookie_file()
    if not cookie_file:
        return ""
    try:
        from http.cookiejar import MozillaCookieJar

        jar = MozillaCookieJar(str(cookie_file))
        jar.load(ignore_discard=True, ignore_expires=True)
        pairs = [f"{c.name}={c.value}" for c in jar]
        return "; ".join(pairs)
    except Exception:
        return ""


def _find_cookie_file() -> Path | None:
    """定位 douyin 平台的 Cookie 文件（backend/cookies/douyin.txt）"""
    # backend/cookies 相对本文件位于 ../../cookies
    base = PACKAGE_DIR.parent.parent / "cookies"
    target = base / "douyin.txt"
    if target.exists():
        return target
    generic = base / "default.txt"
    if generic.exists():
        return generic
    return None
