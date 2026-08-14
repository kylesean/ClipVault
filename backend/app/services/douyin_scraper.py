"""
抖音/TikTok 解析客户端 - 进程内直调抖音 Web 核心算法。
使用 a_bogus 签名绕过抖音反爬，不再依赖独立的 Douyin_TikTok_Download_API 服务。

响应字段结构适配说明（2026-08 实测）：
  新结构：aweme_detail.video.bit_rate[]（各清晰度 play_addr）+
          video.play_addr / download_addr（无水印）/ download_suffix_logo_addr（有水印）
  旧结构：aweme_detail.video_data.nwm_video_url_HQ 等（上游 douyin_api 服务包装格式）
本适配层同时兼容两种结构。
"""

import logging
import re

from app.douyin_core.crawler import DouyinWebCrawler
from app.models.schemas import ParseData, VideoFormat

logger = logging.getLogger(__name__)

_crawler = DouyinWebCrawler()

# 清晰度标签：从 gear_name（如 normal_1080_0）提取高度
_QUALITY_RE = re.compile(r"(\d{3,4})")

# quality_type → 常见清晰度名（兜底用）
_QUALITY_FALLBACK = {
    "1": "1080p",
    "10": "720p",
    "211": "720p",
    "112": "540p",
    "5": "540p",
    "104": "480p",
    "4": "360p",
}


async def parse_douyin_url(url: str) -> ParseData:
    """
    解析抖音链接：提取 aweme_id → 带 a_bogus 签名请求作品详情 → 提取无水印链接。
    """
    aweme_id = await _crawler.get_aweme_id(url)
    data = await _crawler.fetch_one_video(aweme_id)

    video_data = data.get("aweme_detail")
    if not video_data:
        raise ValueError("抖音接口未返回作品数据")

    return _extract_parse_data(video_data)


def _extract_parse_data(video_data: dict) -> ParseData:
    """将抖音接口的响应转换为我们统一的 ParseData 格式"""

    # 提取视频标题
    title = video_data.get("desc") or "未知标题"

    # 提取作者
    author_info = video_data.get("author", {})
    author = (
        author_info.get("nickname")
        or author_info.get("unique_id")
        or "未知作者"
    )

    # 提取时长（毫秒 → 秒）
    video_info = video_data.get("video", {})
    duration_ms = video_info.get("duration") or video_data.get("duration", 0)
    duration = int(duration_ms / 1000) if duration_ms > 1000 else int(duration_ms)

    # 提取封面
    thumbnail = None
    if isinstance(video_info, dict):
        for cover_key in ("origin_cover", "cover", "dynamic_cover"):
            cover = video_info.get(cover_key)
            if isinstance(cover, dict):
                url_list = cover.get("url_list", [])
                if url_list:
                    thumbnail = url_list[0]
                    break
            elif isinstance(cover, str) and cover:
                thumbnail = cover
                break
    if not thumbnail:
        cover_data = video_data.get("cover_data", {})
        if isinstance(cover_data, dict):
            origin = cover_data.get("origin", {})
            if isinstance(origin, dict):
                url_list = origin.get("url_list", [])
                thumbnail = url_list[0] if url_list else None
    if not thumbnail:
        cover = video_data.get("cover", {})
        if isinstance(cover, dict):
            url_list = cover.get("url_list", [])
            thumbnail = url_list[0] if url_list else None
        elif isinstance(cover, str):
            thumbnail = cover

    formats: list[VideoFormat] = _extract_formats(video_data, video_info)

    if not formats:
        raise ValueError("未获取到可用的视频下载链接")

    # 判断平台
    platform = video_data.get("platform", "douyin")

    return ParseData(
        title=title,
        author=author,
        platform=platform,
        duration=duration,
        thumbnail=thumbnail,
        formats=formats,
    )


def _quality_label(gear_name: str | None, quality_type: int | None) -> str:
    """从 gear_name（normal_1080_0）提取清晰度标签"""
    if gear_name:
        match = _QUALITY_RE.search(gear_name)
        if match:
            return f"{match.group(1)}p"
    if quality_type is not None:
        return _QUALITY_FALLBACK.get(str(quality_type), f"quality_{quality_type}")
    return "unknown"


def _extract_formats(video_data: dict, video_info: dict) -> list[VideoFormat]:
    """提取下载链接（兼容新旧两种字段结构）"""
    formats: list[VideoFormat] = []

    def add(quality: str, url: str, ext: str = "mp4") -> None:
        if url and not any(f.url == url for f in formats):
            formats.append(VideoFormat(quality=quality, url=url, size=None, ext=ext))

    # ===== 新结构：video.bit_rate[] / play_addr / download_addr =====
    if isinstance(video_info, dict):
        # 各清晰度（按码率从高到低）
        bit_rates = video_info.get("bit_rate") or []
        for br in bit_rates:
            play_addr = (br.get("play_addr") or {}).get("url_list") or []
            if play_addr:
                quality = _quality_label(br.get("gear_name"), br.get("quality_type"))
                add(f"无水印·{quality}", play_addr[0])

        # 默认播放地址（无水印）
        play_list = (video_info.get("play_addr") or {}).get("url_list") or []
        if play_list:
            add("无水印", play_list[0])

        # 下载地址（无水印）
        dl_list = (video_info.get("download_addr") or {}).get("url_list") or []
        if dl_list:
            add("无水印·下载", dl_list[0])

        # 有水印版本（备选）
        logo = video_info.get("download_suffix_logo_addr") or {}
        logo_list = logo.get("url_list") or []
        if logo_list:
            add("有水印", logo_list[0])

    # ===== 旧结构：video_data.nwm_video_url_HQ 等 =====
    vd = video_data.get("video_data", {})
    if isinstance(vd, dict):
        add("无水印·高清", vd.get("nwm_video_url_HQ"))
        add("无水印", vd.get("nwm_video_url"))
        add("有水印·高清", vd.get("wm_video_url_HQ"))

    return formats
