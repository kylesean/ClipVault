/// 应用全局常量（纯端版：无服务端）
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'ClipVault';

  /// 解析超时时间（秒）
  static const int parseTimeoutSeconds = 30;

  /// 默认最大并发下载数
  static const int defaultMaxConcurrentDownloads = 3;

  /// 支持的视频平台（纯端仅抖音 / TikTok）
  static const List<String> supportedPlatforms = ['douyin', 'tiktok'];

  /// 视频文件扩展名
  static const String videoExtension = '.mp4';

  /// 缩略图文件扩展名
  static const String thumbnailExtension = '.jpg';
}
