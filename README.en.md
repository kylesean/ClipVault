# ClipVault

[中文](./README.md)

A pure on-device Douyin / TikTok download manager: paste a link, sign locally, download watermark-free videos. **No server, works out of the box.**

> Personal sideload + open source. Not published to any app store. For learning and research only.

## Supported Platforms

Douyin / TikTok

## How It Works (serverless)

```
share link → follow short URL to video ID → compute A-Bogus locally
  → call official web APIs directly → watermark-free URLs → download from CDN
```

- **Douyin**: `aweme/v1/web/aweme/detail/` with `A-Bogus` signature (double-SM3 + RC4 + s4-variant Base64) in pure Dart, byte-identical to the Python original (see `test/abogus_test.dart`).
- **TikTok**: parses the embedded `__UNIVERSAL_DATA_FOR_REHYDRATION__` JSON on the video page (no signature needed).
- **Download**: straight from CDN with platform `UA / Referer / Cookie` anti-hotlink headers, no body timeout; large files (≥8MB) download over multiple parallel range connections with automatic single-connection fallback.
- **Identity**: locally forged `msToken / verifyFp` plus optional user Cookie (paste in Settings for best success rate).

## Tech Stack

| Layer | Tech |
|---|---|
| App | Flutter 3.x · Riverpod · GoRouter · Drift · media_kit |
| Signing | Pure Dart (SM3 + A-Bogus, zero crypto deps) |
| Network | Dio (direct CDN) |
| Release | GitHub Actions builds APK / unsigned IPA, CI runs `analyze + test` |

## Quick Start

```bash
git clone https://github.com/kylesean/ClipVault.git
cd ClipVault

make setup   # flutter pub get
make run     # run on device/emulator
```

Build your own packages:

```bash
make apk   # Android APK (release)
make ipa   # unsigned iOS (macOS only, for sideloading)
```

## Settings Tips

- **Douyin**: usually works with zero config. On failure, paste your browser Cookie for `douyin.com` in Settings.
- **TikTok**: needs a network that can reach TikTok directly (system-level VPN where it's blocked; no in-app proxy).

## Project Structure

```
├── lib/
│   ├── core/             # Theme, constants, utils, errors
│   ├── features/
│   │   ├── decode/       # Pure-Dart signing & parsing core
│   │   │   ├── sm3.dart        # SM3 (GB/T 32905), dependency-free
│   │   │   ├── abogus.dart     # A-Bogus (line-by-line port of Python original)
│   │   │   └── douyin_api.dart # Signed Douyin API + TikTok page parsing
│   │   ├── home/ library/ download/ settings/ player/
│   └── shared/           # Database / download service / parse client
├── test/
│   ├── sm3_test.dart       # SM3 standard vectors
│   ├── abogus_test.dart    # Byte-identical signature vectors vs Python
│   └── ...                 # Controller / utils / widget tests
├── .github/workflows/    # CI (analyze + test + packaging)
└── Makefile              # Common commands
```

## Re-sync Guide (when Douyin changes signing)

Douyin rotates signing params every 2–4 months (`s4 alphabet / ua_code / version`). Symptom: everything fails at once.

1. Run `flutter test test/abogus_test.dart` to see which vector breaks;
2. Locate with the `debugParamsCode / debugMethodCode` probes in `abogus.dart`;
3. Port upstream changes: https://github.com/Evil0ctal/Douyin_TikTok_Download_API , add new vectors;
4. `make apk` and reinstall — no store review needed.

## Credits & License Notes

- [Evil0ctal/Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API) (Apache-2.0) — signature algorithm & params source
- [JoeanAmier/TikTokDownloader](https://github.com/JoeanAmier/TikTokDownloader) (GPLv3) — original author of `abogus.py`; `lib/features/decode/abogus.dart` is a Dart port, original attribution kept
- [media-kit](https://github.com/media-kit/media-kit) — Flutter video playback

> Files under `lib/features/decode/` follow their upstream licenses (see file headers); everything else is MIT.

## Disclaimer

Personal learning and research only. Do not use commercially or infringe others' rights. Bulk scraping may violate platform ToS — use at your own risk.

## License

[MIT](./LICENSE)
