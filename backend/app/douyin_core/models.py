# ==============================================================================
# Copyright (C) 2021 Evil0ctal (Douyin_TikTok_Download_API, Apache-2.0)
#
# 精简迁移自 crawlers/douyin/web/models.py 的 BaseRequestModel（PostDetail）。
# 注意：上游的 msToken 字段默认值会在 import 时发起网络请求，
# 此处改为空串（fetch_one_video 中本就会被覆盖为空），避免导入副作用。
# ==============================================================================

from pydantic import BaseModel


class PostDetail(BaseModel):
    """作品详情请求参数（常量必须与上游保持一致，参与 a_bogus 签名）"""

    device_platform: str = "webapp"
    aid: str = "6383"
    channel: str = "channel_pc_web"
    pc_client_type: int = 1
    version_code: str = "290100"
    version_name: str = "29.1.0"
    cookie_enabled: str = "true"
    screen_width: int = 1920
    screen_height: int = 1080
    browser_language: str = "zh-CN"
    browser_platform: str = "Win32"
    browser_name: str = "Chrome"
    browser_version: str = "130.0.0.0"
    browser_online: str = "true"
    engine_name: str = "Blink"
    engine_version: str = "130.0.0.0"
    os_name: str = "Windows"
    os_version: str = "10"
    cpu_core_num: int = 12
    device_memory: int = 8
    platform: str = "PC"
    downlink: str = "10"
    effective_type: str = "4g"
    from_user_page: str = "1"
    locate_query: str = "false"
    need_time_list: str = "1"
    pc_libra_divert: str = "Windows"
    publish_video_strategy_type: str = "2"
    round_trip_time: str = "0"
    show_live_replay_strategy: str = "1"
    time_list_query: str = "0"
    whale_cut_token: str = ""
    update_version_code: str = "170400"
    aweme_id: str
    msToken: str = ""
