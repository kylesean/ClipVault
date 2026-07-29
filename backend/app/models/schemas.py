from pydantic import BaseModel


class ParseRequest(BaseModel):
    url: str


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
