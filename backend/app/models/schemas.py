from pydantic import BaseModel


class ParseRequest(BaseModel):
    url: str


class CookieRefreshRequest(BaseModel):
    """Cookie 刷新请求 - 支持直接传入浏览器 Cookie 字符串"""
    service: str | None = None
    cookie: str | None = None


class VideoFormat(BaseModel):
    quality: str
    url: str
    size: int | None = None
    ext: str = "mp4"


class ParseData(BaseModel):
    title: str
    author: str
    platform: str
    duration: int
    thumbnail: str | None = None
    formats: list[VideoFormat]


class ParseResponse(BaseModel):
    code: int
    data: ParseData | None = None
    message: str | None = None
