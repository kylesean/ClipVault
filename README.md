# ClipVault

短视频下载管理工具，支持多平台链接解析与无水印下载。

## 支持平台

抖音 / TikTok / Bilibili / YouTube / 快手 / 小红书 / 微博等

## 技术栈

- **前端**: Flutter 3.x + Riverpod + GoRouter + Drift
- **后端**: FastAPI + yt-dlp + [Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API)
- **部署**: Docker Compose

## 快速开始

```bash
# 克隆（含子模块）
git clone --recurse-submodules https://github.com/你的用户名/clip_vault.git
cd clip_vault

# 初始化环境
make setup

# 启动后端
make dev

# 运行 Flutter 应用
flutter run
```

## 构建

```bash
make apk    # Android APK
make deploy # Docker 部署后端
```

## 项目结构

```
├── lib/                # Flutter 前端
│   ├── core/           # 主题、常量、工具
│   ├── features/       # 功能模块（首页/资源库/下载/设置/播放器）
│   └── shared/         # 共享服务（数据库/网络/下载）
├── backend/            # 解析服务
│   ├── app/            # FastAPI 主服务
│   └── douyin_api/     # 抖音解析引擎（Git Submodule）
├── docker-compose.yml  # 一键部署
└── Makefile            # 常用命令
```

## 说明

本项目仅供个人学习研究使用，请勿用于商业用途。

## License

MIT
