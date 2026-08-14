import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.routers.cookies import router as cookies_router
from app.routers.download_proxy import router as download_proxy_router
from app.routers.parse import limiter, router as parse_router
from app.services.cookie_refresh_service import start_cookie_scheduler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 环境变量配置
ALLOWED_ORIGINS = os.getenv(
    "CLIPVAULT_CORS_ORIGINS", "*"
).split(",")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI 生命周期：启动时开启 Cookie 自动刷新调度器"""
    task = asyncio.create_task(start_cookie_scheduler())
    logger.info("ClipVault Parse Service 已启动")
    yield
    task.cancel()
    try:
        await task
    except (asyncio.CancelledError, Exception):
        pass


app = FastAPI(
    title="ClipVault Parse Service",
    description="视频链接解析服务 - 抖音/TikTok/B站 + yt-dlp 1800+ 站点",
    version="1.0.0",
    lifespan=lifespan,
)

# 速率限制
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# 限流中间件必须最先注册（最后包裹），保证对所有路由生效
app.add_middleware(SlowAPIMiddleware)

# CORS
# 注意：allow_origins="*" 与 allow_credentials=True 组合是非法的（浏览器会拒绝），
# 仅在显式配置了具体来源时才启用 credentials
cors_credentials = len(ALLOWED_ORIGINS) > 1 or (ALLOWED_ORIGINS != ["*"])
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=cors_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(parse_router)
app.include_router(cookies_router)
app.include_router(download_proxy_router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.getenv("CLIPVAULT_PORT", "8000")),
    )
