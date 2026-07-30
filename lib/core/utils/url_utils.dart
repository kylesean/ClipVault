/// URL 验证与提取工具
class UrlUtils {
  UrlUtils._();

  /// 已知平台链接模式
  static final _platformPatterns = <String, RegExp>{
    'douyin': RegExp(r'(v\.douyin\.com|www\.douyin\.com|www\.iesdouyin\.com)'),
    'tiktok': RegExp(r'(tiktok\.com|vm\.tiktok\.com|vt\.tiktok\.com)'),
    'bilibili': RegExp(r'(bilibili\.com|b23\.tv)'),
    'kuaishou': RegExp(r'(kuaishou\.com|v\.kuaishou\.com)'),
    'xiaohongshu': RegExp(r'(xiaohongshu\.com|xhslink\.com)'),
    'youtube': RegExp(r'(youtube\.com|youtu\.be)'),
    'instagram': RegExp(r'(instagram\.com|instagr\.am)'),
    'weibo': RegExp(r'(weibo\.com|weibo\.cn)'),
  };

  /// 通用 URL 正则
  static final _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  /// 从文本中提取 URL
  static String? extractUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    return match?.group(0);
  }

  /// 从文本中提取所有 URL
  static List<String> extractAllUrls(String text) {
    return _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// 判断是否为有效视频链接
  static bool isValidVideoUrl(String text) {
    final url = extractUrl(text);
    if (url == null) return false;
    return _platformPatterns.values.any((p) => p.hasMatch(url));
  }

  /// 识别链接所属平台
  static String? detectPlatform(String url) {
    for (final entry in _platformPatterns.entries) {
      if (entry.value.hasMatch(url)) return entry.key;
    }
    return null;
  }

  /// 获取平台显示名称
  static String platformDisplayName(String? platform) {
    return switch (platform) {
      'douyin' => '抖音',
      'tiktok' => 'TikTok',
      'bilibili' => 'B站',
      'kuaishou' => '快手',
      'xiaohongshu' => '小红书',
      'youtube' => 'YouTube',
      'instagram' => 'Instagram',
      'weibo' => '微博',
      _ => '其他',
    };
  }
}
