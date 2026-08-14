# douyin_core — 抖音 Web 解析核心（内嵌迁移版）

本目录从 [Evil0ctal/Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API)
（Apache-2.0）精简迁移而来，用于进程内解析抖音视频（a_bogus 签名绕过反爬），
**不再依赖独立的 douyin_api 服务与 git 子模块**。

## 文件说明

| 文件 | 来源 | 说明 |
|------|------|------|
| `abogus.py` | 上游逐字节保留（含原始 GPL-3.0 头，源自 JoeanAmier/TikTokDownloader） | A-Bogus 签名算法，**勿改动** |
| `token_manager.py` | 上游 `utils.py` 精简 | msToken/ttwid/verify_fp 生成 + A-Bogus 管理 |
| `fetchers.py` | 上游 `utils.py` 精简 | 分享链接 → aweme_id |
| `models.py` | 上游 `models.py` 精简 | 作品详情请求参数（参与签名，**勿改动**） |
| `crawler.py` | 上游 `web_crawler.py` 精简 | 请求构造与数据抓取 |
| `config.py` / `config.yaml` | 上游 `config.yaml` 精简 | 静态参数（**不含 Cookie**） |

## 许可证

- `abogus.py` 保留上游 GPL-3.0 许可头（源自 JoeanAmier/TikTokDownloader），
  其余精简代码源自 Apache-2.0 项目。使用时请保留各文件头部的版权声明。
- 本项目为自托管/个人使用场景，GPL 部分不会被对外分发。

## Cookie 策略

Cookie 统一存储在 `backend/cookies/douyin.txt`（Netscape 格式）：
- 上传：`POST /api/cookies/douyin`
- 自动刷新：服务启动时及每 12h 由 `cookie_refresh_service` 本地生成反爬参数

## 上游同步（抖音改版后执行）

```bash
make update-douyin-core   # 即 python3 scripts/sync_douyin_core.py
```

仅自动同步 `abogus.py` 与 `config.yaml`；其余文件为人工精简版，需对照上游 diff 后手动更新。
