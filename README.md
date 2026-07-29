# ClipVault

[English](./README.en.md)

一个跨平台的短视频下载管理工具，粘贴链接即可解析并下载无水印视频。

## 支持平台

抖音 / TikTok / Bilibili / YouTube / 快手 / 小红书 / 微博 等 1800+ 站点

## 它是怎么工作的

采用双引擎解析架构：

- **主引擎**：基于 [Evil0ctal/Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API) 处理抖音/TikTok/B站的签名与反爬
- **兜底引擎**：[yt-dlp](https://github.com/yt-dlp/yt-dlp) 覆盖其余 1800+ 站点

请求进来后先走主引擎，失败则自动降级到 yt-dlp，对使用者透明。

## 技术栈

| 层 | 技术 |
|---|---|
| 前端 | Flutter 3.x · Riverpod · GoRouter · Drift · media_kit |
| 后端 | FastAPI · yt-dlp · HTTPX |
| 解析引擎 | Douyin_TikTok_Download_API（Git Submodule） |
| 部署 | Docker Compose · GitHub Actions CI |

## 快速开始

```bash
# 克隆（含子模块）
git clone --recurse-submodules https://github.com/kylesean/ClipVault.git
cd ClipVault

# 一键初始化环境
make setup

# 启动后端服务
make dev

# 运行 App
flutter run
```

## 构建 & 部署

```bash
make apk      # 构建 Android APK
make deploy   # Docker 一键部署后端
make update-douyin  # 同步上游解析引擎更新
```

## 项目结构

```
├── lib/                  # Flutter 前端
│   ├── core/             # 主题、常量、工具类
│   ├── features/         # 功能模块（首页/资源库/下载/设置/播放器）
│   └── shared/           # 共享服务（数据库/网络/下载）
├── backend/              # 解析后端
│   ├── app/              # FastAPI 主服务（路由/服务/模型）
│   └── douyin_api/       # 抖音解析引擎（Git Submodule）
├── .github/workflows/    # CI 自动构建
├── docker-compose.yml    # 后端编排
└── Makefile              # 常用命令入口
```

## 致谢

- [Evil0ctal/Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [media-kit](https://github.com/media-kit/media-kit)

## 免责声明

本项目仅供个人学习与技术研究使用，请勿用于任何商业用途或侵犯他人权益的行为。

## License

[MIT](./LICENSE)
