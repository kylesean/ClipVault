# ==============================================================================
# Copyright (C) 2021 Evil0ctal (Douyin_TikTok_Download_API, Apache-2.0)
#
# 本文件是从 https://github.com/Evil0ctal/Douyin_TikTok_Download_API
# 的 crawlers/douyin/web/web_crawler.py 精简迁移而来，仅保留 ClipVault
# 实际使用的方法（fetch_one_video / get_aweme_id / gen_* / update_cookie），
# 并使用 httpx 直接实现 HTTP 层，不再依赖上游的 BaseCrawler 与 FastAPI。
# ==============================================================================

import logging
from urllib.parse import urlencode

import httpx

from app.douyin_core import config as core_config
from app.douyin_core.fetchers import AwemeIdFetcher
from app.douyin_core.models import PostDetail
from app.douyin_core.token_manager import (
    APIConnectionError,
    APIResponseError,
    BogusManager,
    TokenManager,
    VerifyFpManager,
)

logger = logging.getLogger(__name__)

# 作品详情接口（常量与上游一致）
POST_DETAIL_ENDPOINT = "https://www.douyin.com/aweme/v1/web/aweme/detail/"


class DouyinWebCrawler:
    """抖音 Web 数据爬虫（进程内直调，无独立服务）"""

    def __init__(self):
        self._headers = core_config.get_headers

    async def fetch_one_video(self, aweme_id: str) -> dict:
        """
        获取单个作品数据。
        构造带 a_bogus 签名的请求 URL 并拉取 JSON。
        """
        headers = self._headers()
        params = PostDetail(aweme_id=aweme_id)
        params_dict = params.model_dump()
        # 与上游一致：msToken 在签名前置空
        params_dict["msToken"] = ""
        a_bogus = BogusManager.ab_model_2_endpoint(
            params_dict, core_config.get_user_agent()
        )
        endpoint = (
            f"{POST_DETAIL_ENDPOINT}?{urlencode(params_dict)}&a_bogus={a_bogus}"
        )

        try:
            async with httpx.AsyncClient(
                headers=headers,
                timeout=httpx.Timeout(15.0),
                **core_config.get_http_kwargs(),
            ) as client:
                response = await client.get(endpoint)
                response.raise_for_status()
                return response.json()
        except httpx.RequestError as e:
            raise APIConnectionError(f"请求抖音接口失败: {e}")
        except httpx.HTTPStatusError as e:
            raise APIResponseError(
                f"抖音接口返回 {e.response.status_code}"
            )

    async def get_aweme_id(self, url: str) -> str:
        """从分享链接提取 aweme_id"""
        return await AwemeIdFetcher.get_aweme_id(url)

    async def gen_real_msToken(self) -> str:
        return TokenManager.gen_real_msToken()

    async def gen_ttwid(self) -> str:
        return TokenManager.gen_ttwid()

    async def gen_verify_fp(self) -> str:
        return VerifyFpManager.gen_verify_fp()

    async def gen_s_v_web_id(self) -> str:
        return VerifyFpManager.gen_s_v_web_id()

    def update_cookie(self, cookie: str) -> None:
        """
        更新 Cookie（兼容上游接口签名）。
        Cookie 统一从 backend/cookies/douyin.txt 读取，此处仅记录日志。
        """
        logger.info("Cookie 已更新（来源: backend/cookies/douyin.txt）")
