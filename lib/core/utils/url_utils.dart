/// URL 验证与提取工具
class UrlUtils {
  UrlUtils._();

  /// 已知平台域名（按 host 匹配，避免子串误判）
  static const Map<String, List<String>> _platformDomains = {
    'douyin': ['douyin.com', 'v.douyin.com', 'iesdouyin.com'],
    'tiktok': ['tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'],
    'bilibili': ['bilibili.com', 'b23.tv'],
    'kuaishou': ['kuaishou.com', 'v.kuaishou.com'],
    'xiaohongshu': ['xiaohongshu.com', 'xhslink.com'],
    'youtube': ['youtube.com', 'youtu.be'],
    'instagram': ['instagram.com', 'instagr.am'],
    'weibo': ['weibo.com', 'weibo.cn'],
  };

  /// 通用 URL 正则
  static final _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  /// 常见尾部噪声：中英文标点 + 中文汉字（分享文本常见 "链接，快去下载"）
  /// 视频分享 URL 的路径中不会包含未编码的中文，可安全裁剪
  static final _trailingJunk = RegExp(
    r'''[,.;:!?()\[\]{}，。；：！？、…“”"'》」】）』「」『』〔〕\u4e00-\u9fff]+$''',
  );

  /// 从文本中提取 URL（裁剪尾部噪声）
  static String? extractUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;
    return match.group(0)!.replaceAll(_trailingJunk, '');
  }

  /// 从文本中提取所有 URL
  static List<String> extractAllUrls(String text) {
    return _urlRegex
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(_trailingJunk, ''))
        .toList();
  }

  static String? _hostOf(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.toLowerCase();
  }

  /// 判断是否为有效视频链接
  static bool isValidVideoUrl(String text) {
    return detectPlatform(text) != null;
  }

  /// 识别链接所属平台（按 host 精确匹配域名或子域）
  static String? detectPlatform(String text) {
    final host = _hostOf(text);
    if (host == null) return null;
    for (final entry in _platformDomains.entries) {
      for (final domain in entry.value) {
        if (host == domain || host.endsWith('.$domain')) {
          return entry.key;
        }
      }
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
