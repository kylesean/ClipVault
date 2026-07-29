# ClipVault

[中文](./README.md)

A cross-platform short video download manager. Paste a link, get a watermark-free video.

## Supported Platforms

Douyin / TikTok / Bilibili / YouTube / Kuaishou / Xiaohongshu / Weibo & 1800+ sites

## How It Works

Dual-engine parsing architecture:

- **Primary**: [Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API) — handles Douyin/TikTok/Bilibili with built-in signature algorithms
- **Fallback**: [yt-dlp](https://github.com/yt-dlp/yt-dlp) — covers 1800+ other sites

Requests hit the primary engine first; on failure, they silently fall back to yt-dlp.

## Tech Stack

| Layer | Tech |
|---|---|
| Frontend | Flutter 3.x · Riverpod · GoRouter · Drift · media_kit |
| Backend | FastAPI · yt-dlp · HTTPX |
| Parse Engine | Douyin_TikTok_Download_API (Git Submodule) |
| Deploy | Docker Compose · GitHub Actions CI |

## Quick Start

```bash
git clone --recurse-submodules https://github.com/kylesean/ClipVault.git
cd ClipVault

make setup    # Initialize environment
make dev      # Start backend services
flutter run   # Run the app
```

## Build & Deploy

```bash
make apk            # Build Android APK
make deploy         # Docker deploy backend
make update-douyin  # Sync upstream parse engine
```

## Project Structure

```
├── lib/                  # Flutter frontend
│   ├── core/             # Theme, constants, utils
│   ├── features/         # Modules (home/library/download/settings/player)
│   └── shared/           # Shared services (database/network/download)
├── backend/              # Parse backend
│   ├── app/              # FastAPI service (routers/services/models)
│   └── douyin_api/       # Douyin parse engine (Git Submodule)
├── .github/workflows/    # CI builds
├── docker-compose.yml    # Backend orchestration
└── Makefile              # Common commands
```

## Credits

- [Evil0ctal/Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API) — Douyin/TikTok/Bilibili parsing with X-Bogus / A-Bogus signatures
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — Universal video extraction engine
- [media-kit](https://github.com/media-kit/media-kit) — Video playback for Flutter

## Disclaimer

This project is for personal learning and research purposes only. Do not use it for any commercial purposes or actions that infringe upon others' rights.

## License

[MIT](./LICENSE)
