"""
API 认证 - 可选的静态 Token 鉴权。
通过环境变量 CLIPVAULT_API_TOKEN 启用：
  - 未设置：所有接口保持开放（默认，兼容现有部署）
  - 已设置：敏感接口要求请求头 X-API-Token 匹配
"""

import logging
import os

from fastapi import Header, HTTPException

logger = logging.getLogger(__name__)

API_TOKEN = os.getenv("CLIPVAULT_API_TOKEN", "").strip()


def auth_enabled() -> bool:
    return bool(API_TOKEN)


def verify_token(x_api_token: str | None = None) -> bool:
    if not auth_enabled():
        return True
    return bool(x_api_token) and x_api_token == API_TOKEN


def require_token(x_api_token: str | None = Header(default=None)):
    """FastAPI 依赖：需要认证时校验 X-API-Token 请求头"""
    if auth_enabled() and not verify_token(x_api_token):
        raise HTTPException(status_code=401, detail="未授权")
    return None
