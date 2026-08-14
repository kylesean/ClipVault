# ==============================================================================
# Copyright (C) 2021 Evil0ctal (Douyin_TikTok_Download_API, Apache-2.0)
#
# 本文件是从 https://github.com/Evil0ctal/Douyin_TikTok_Download_API
# 的 crawlers/douyin/web/utils.py 精简迁移而来：
#   - TokenManager.gen_real_msToken / gen_false_msToken / gen_ttwid
#   - VerifyFpManager.gen_verify_fp / gen_s_v_web_id
#   - BogusManager.ab_model_2_endpoint
# 仅保留了 ClipVault 实际使用的类与方法，并移除了对上游配置的强依赖。
# ==============================================================================

import json
import logging
import random
import time
from urllib.parse import quote

import httpx

from app.douyin_core import config as core_config
from app.douyin_core.abogus import ABogus

logger = logging.getLogger(__name__)


class APIError(Exception):
    """抖音核心 API 错误基类"""

    def __init__(self, status_code=None, *args):
        super().__init__(*args)
        self.status_code = status_code


class APIConnectionError(APIError):
    pass


class APIResponseError(APIError):
    pass


def gen_random_str(randomlength: int) -> str:
    """生成指定长度的随机字符串"""
    base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(random.choice(base) for _ in range(randomlength))


def get_timestamp() -> int:
    """当前时间戳（毫秒）"""
    return int(time.time() * 1000)


class TokenManager:
    """抖音请求令牌生成（msToken / ttwid）"""

    _conf = core_config.config["TokenManager"]["douyin"]
    _ms_token_conf = _conf.get("msToken", {})
    _ttwid_conf = _conf.get("ttwid", {})

    @classmethod
    def gen_real_msToken(cls) -> str:
        """
        调用字节跳动 mssdk 端点生成真实 msToken。
        失败时返回本地伪造值（与上游行为一致，保证请求流程不中断）。
        """
        payload = json.dumps(
            {
                "magic": cls._ms_token_conf["magic"],
                "version": cls._ms_token_conf["version"],
                "dataType": cls._ms_token_conf["dataType"],
                "strData": cls._ms_token_conf["strData"],
                "tspFromClient": get_timestamp(),
            }
        )
        headers = {
            "User-Agent": cls._ms_token_conf["User-Agent"],
            "Content-Type": "application/json",
        }
        try:
            with httpx.Client(
                timeout=10,
                **core_config.get_http_kwargs(),
            ) as client:
                response = client.post(
                    cls._ms_token_conf["url"], content=payload, headers=headers
                )
                response.raise_for_status()
                ms_token = str(httpx.Cookies(response.cookies).get("msToken"))
                if len(ms_token) not in (120, 128):
                    raise APIResponseError("msToken 响应长度不符合要求")
                return ms_token
        except Exception as e:
            logger.warning("生成真实 msToken 失败，改用本地伪造值: %s", e)
            return cls.gen_false_msToken()

    @classmethod
    def gen_false_msToken(cls) -> str:
        """生成随机 msToken（本地伪造，无网络依赖）"""
        return gen_random_str(126) + "=="

    @classmethod
    def gen_ttwid(cls) -> str:
        """生成请求必带的 ttwid（设备标识）"""
        try:
            with httpx.Client(
                timeout=10,
                **core_config.get_http_kwargs(),
            ) as client:
                response = client.post(
                    cls._ttwid_conf["url"], content=cls._ttwid_conf["data"]
                )
                response.raise_for_status()
                ttwid = str(httpx.Cookies(response.cookies).get("ttwid"))
                if not ttwid:
                    raise APIResponseError("ttwid 响应为空")
                return ttwid
        except Exception as e:
            raise APIConnectionError(f"生成 ttwid 失败: {e}")


class VerifyFpManager:
    """设备指纹生成（verify_fp / s_v_web_id，纯本地算法）"""

    @classmethod
    def gen_verify_fp(cls) -> str:
        base_str = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        t = len(base_str)
        milliseconds = int(round(time.time() * 1000))
        base36 = ""
        while milliseconds > 0:
            remainder = milliseconds % 36
            if remainder < 10:
                base36 = str(remainder) + base36
            else:
                base36 = chr(ord("a") + remainder - 10) + base36
            milliseconds = int(milliseconds / 36)
        r = base36
        o = [""] * 36
        o[8] = o[13] = o[18] = o[23] = "_"
        o[14] = "4"

        for i in range(36):
            if not o[i]:
                n = 0 or int(random.random() * t)
                if i == 19:
                    n = 3 & n | 8
                o[i] = base_str[n]

        return "verify_" + r + "_" + "".join(o)

    @classmethod
    def gen_s_v_web_id(cls) -> str:
        return cls.gen_verify_fp()


class BogusManager:
    """A-Bogus 签名生成（当前抖音 Web API 唯一在用的加密参数）"""

    @classmethod
    def ab_model_2_endpoint(cls, params: dict, user_agent: str) -> str:
        if not isinstance(params, dict):
            raise TypeError("参数必须是字典类型")
        try:
            ab_value = ABogus().get_value(params)
        except Exception as e:
            raise RuntimeError(f"生成 A-Bogus 失败: {e}")
        return quote(ab_value, safe="")
