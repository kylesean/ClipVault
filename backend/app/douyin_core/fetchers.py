# ==============================================================================
# Copyright (C) 2021 Evil0ctal (Douyin_TikTok_Download_API, Apache-2.0)
#
# 精简迁移自 crawlers/douyin/web/utils.py 的 AwemeIdFetcher.get_aweme_id。
# ==============================================================================

import logging
import re

import httpx

from app.douyin_core import config as core_config
from app.douyin_core.token_manager import (
    APIConnectionError,
    APIResponseError,
)

logger = logging.getLogger(__name__)


class AwemeIdFetcher:
    """从分享链接/作品页 URL 提取 aweme_id"""

    _DOUYIN_VIDEO_URL_PATTERN = re.compile(r"video/([^/?]*)")
    _DOUYIN_VIDEO_URL_PATTERN_NEW = re.compile(r"[?&]vid=(\d+)")
    _DOUYIN_NOTE_URL_PATTERN = re.compile(r"note/([^/?]*)")
    _DOUYIN_DISCOVER_URL_PATTERN = re.compile(r"modal_id=([0-9]+)")

    @classmethod
    async def get_aweme_id(cls, url: str) -> str:
        """
        从单个 url 中获取 aweme_id（跟随重定向解析短链）
        """
        if not isinstance(url, str):
            raise TypeError("参数必须是字符串类型")

        try:
            async with httpx.AsyncClient(
                timeout=10,
                follow_redirects=True,
                **core_config.get_http_kwargs(),
            ) as client:
                response = await client.get(url)
                response.raise_for_status()
                response_url = str(response.url)
        except httpx.RequestError as e:
            raise APIConnectionError(f"短链解析失败，请检查网络环境。链接：{url}，错误：{e}")
        except httpx.HTTPStatusError as e:
            raise APIResponseError(f"链接：{e.response.url}，状态码 {e.response.status_code}")

        # 按顺序尝试匹配视频 ID
        for pattern in [
            cls._DOUYIN_VIDEO_URL_PATTERN,
            cls._DOUYIN_VIDEO_URL_PATTERN_NEW,
            cls._DOUYIN_NOTE_URL_PATTERN,
            cls._DOUYIN_DISCOVER_URL_PATTERN,
        ]:
            match = pattern.search(response_url)
            if match:
                return match.group(1)

        raise APIResponseError("未在响应的地址中找到 aweme_id，检查链接是否为作品页")
