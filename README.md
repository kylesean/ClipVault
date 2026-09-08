# ClipVault

[English](./README.en.md)

一个纯端的抖音 / TikTok 下载管理工具：粘贴链接，本地签名解析，下载无水印视频。**无服务端，开箱即用。**

> 自用侧载 + 开源项目，不上架应用商店。仅供个人学习与技术研究。

## 支持平台

抖音 / TikTok

## 它是怎么工作的（纯端）

```
分享链接 → 跟随短链拿作品 ID → 本地算 A-Bogus 签名 → 直调官方 Web 接口
                                              → 拿无水印直链 → 直连 CDN 下载
```

- **抖音**：`aweme/v1/web/aweme/detail/`，`A-Bogus` 签名（`SM3 双哈希 + RC4 + s4 变体 Base64`）纯 Dart 实现，与 Python 原版逐字节对齐（`test/abogus_test.dart` 交叉验证）。
- **TikTok**：作品页内嵌 `__UNIVERSAL_DATA_FOR_REHYDRATION__` JSON，免签名解析。
- **下载**：直连 CDN，自动带平台 `UA / Referer / Cookie` 防盗链头，无大小超时限制；大文件（≥8MB）多连接分段并下，失败自动回退单连接。
- **身份**：本地伪造 `msToken / verifyFp` + 可选用户 Cookie（设置页粘贴，成功率最高）。

## 技术栈

| 层 | 技术 |
|---|---|
| App | Flutter 3.x · Riverpod · GoRouter · Drift · media_kit |
| 签名 | 纯 Dart（SM3 + A-Bogus，无第三方 crypto 依赖） |
| 网络 | Dio 直连 CDN |
| 发布 | GitHub Actions 自动打 APK / 免签 IPA，CI 跑 `analyze + test` |

## 快速开始

```bash
git clone https://github.com/kylesean/ClipVault.git
cd ClipVault

make setup   # flutter pub get
make run     # 连设备/模拟器运行
```

构建自用包：

```bash
make apk   # Android APK（release）
make ipa   # iOS 免签（macOS only，侧载用）
```

## 设置建议

- **抖音**：一般零配置可用。解析失败 → 设置页粘贴浏览器 `douyin.com` 的 Cookie。
- **TikTok**：需要能直连 TikTok 的网络环境（国内需系统级梯子，App 内无代理设置）。

## 项目结构

```
├── lib/
│   ├── core/             # 主题、常量、工具、错误类型
│   ├── features/
│   │   ├── decode/       # 纯 Dart 签名与解析核心
│   │   │   ├── sm3.dart        # SM3（GB/T 32905），无外部依赖
│   │   │   ├── abogus.dart     # A-Bogus 签名（Python 原版逐行移植）
│   │   │   └── douyin_api.dart # 抖音签名接口 + TikTok 页面解析
│   │   ├── home/ library/ download/ settings/ player/
│   └── shared/           # 数据库 / 下载服务 / 解析客户端
├── test/
│   ├── sm3_test.dart       # SM3 标准向量
│   ├── abogus_test.dart    # 与 Python 原实现逐字节对齐的签名向量
│   └── ...                 # 控制器 / 工具 / widget 测试
├── .github/workflows/    # CI（analyze + test + 打包）
└── Makefile              # 常用命令入口
```

## 跟版指南（抖音改版后）

抖音约 2–4 个月小换一次签名参数（`s4 字母表 / ua_code / 版本号`），症状是突然全解析失败：

1. `flutter test test/abogus_test.dart` 看向量哪条挂了；
2. 用 `abogus.dart` 里的 `debugParamsCode / debugMethodCode` 探针定位；
3. 对照上游更新：https://github.com/Evil0ctal/Douyin_TikTok_Download_API ，补新向量；
4. `make apk` 重打侧载包即可，无需等商店审核。

## 致谢与许可说明

- [Evil0ctal/Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API)（Apache-2.0）—— 签名算法与参数来源
- [JoeanAmier/TikTokDownloader](https://github.com/JoeanAmier/TikTokDownloader)（GPLv3）—— `abogus.py` 原始作者，`lib/features/decode/abogus.dart` 为其 Dart 移植，保留原作者信息
- [media-kit](https://github.com/media-kit/media-kit) —— Flutter 视频播放

> `lib/features/decode/` 下文件遵循上游许可要求（见各文件头注释），其余代码 MIT。

## 免责声明

本项目仅供个人学习与技术研究使用，请勿用于任何商业用途或侵犯他人权益的行为。批量爬取可能违反平台服务条款，后果自负。

## License

[MIT](./LICENSE)
