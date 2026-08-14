# ==============================================================================
# Copyright (C) 2021 Evil0ctal (Douyin_TikTok_Download_API, Apache-2.0)
#
# 抖音 Web 解析核心（从上游 Douyin_TikTok_Download_API 精简迁移，进程内直调）。
#
# 组成：
#   abogus.py        - A-Bogus 签名算法（逐字节保留上游实现，含原始许可头）
#   token_manager.py - msToken / ttwid / verify_fp 生成 + A-Bogus 管理
#   fetchers.py      - 从分享链接提取 aweme_id
#   models.py        - 作品详情请求参数（参与签名，勿改）
#   crawler.py       - 请求构造与数据抓取（含 a_bogus 签名拼接）
#   config.py/yaml   - 静态参数配置（Cookie 不在此保存）
#
# 上游同步：python scripts/sync_douyin_core.py
# ==============================================================================

from app.douyin_core.crawler import DouyinWebCrawler

__all__ = ["DouyinWebCrawler"]
