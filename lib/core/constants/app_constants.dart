/// 应用全局常量
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'ClipVault';

  /// 后端解析服务地址
  /// 模拟器用 10.0.2.2，真机用局域网 IP
  static const String parseApiBaseUrl = 'http://192.168.31.16:8000';

  /// 解析超时时间（秒）
  static const int parseTimeoutSeconds = 15;

  /// 默认最大并发下载数
  static const int defaultMaxConcurrentDownloads = 3;

  /// 支持的视频平台
  static const List<String> supportedPlatforms = [
    'douyin',
    'bilibili',
    'kuaishou',
    'xiaohongshu',
    'youtube',
    'weibo',
  ];

  /// 视频文件扩展名
  static const String videoExtension = '.mp4';

  /// 缩略图文件扩展名
  static const String thumbnailExtension = '.jpg';
}
