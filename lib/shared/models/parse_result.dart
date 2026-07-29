/// 后端解析 API 返回的视频信息
class ParseResult {
  final String title;
  final String author;
  final String platform;
  final int duration;
  final String? thumbnail;
  final List<VideoFormat> formats;

  const ParseResult({
    required this.title,
    required this.author,
    required this.platform,
    required this.duration,
    this.thumbnail,
    required this.formats,
  });

  /// 获取最佳格式（最高画质 mp4）
  VideoFormat? get bestFormat {
    if (formats.isEmpty) return null;
    final mp4s = formats.where((f) => f.ext == 'mp4').toList();
    if (mp4s.isNotEmpty) return mp4s.last;
    return formats.last;
  }

  factory ParseResult.fromJson(Map<String, dynamic> json) {
    return ParseResult(
      title: json['title'] as String? ?? '未知标题',
      author: json['author'] as String? ?? '未知作者',
      platform: json['platform'] as String? ?? 'unknown',
      duration: json['duration'] as int? ?? 0,
      thumbnail: json['thumbnail'] as String?,
      formats: (json['formats'] as List<dynamic>?)
              ?.map((f) => VideoFormat.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// 视频格式/清晰度
class VideoFormat {
  final String quality;
  final String url;
  final int? size;
  final String ext;

  const VideoFormat({
    required this.quality,
    required this.url,
    this.size,
    required this.ext,
  });

  factory VideoFormat.fromJson(Map<String, dynamic> json) {
    return VideoFormat(
      quality: json['quality'] as String? ?? 'unknown',
      url: json['url'] as String? ?? '',
      size: json['size'] as int?,
      ext: json['ext'] as String? ?? 'mp4',
    );
  }
}
