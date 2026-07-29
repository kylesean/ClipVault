/// 下载任务状态
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
}

/// 下载任务模型
class DownloadTask {
  final String id;
  final String url;
  final String? title;
  final String? author;
  final String? platform;
  final String? thumbnailUrl;
  final DownloadStatus status;
  final double progress;
  final int? speedBytesPerSec;
  final int? totalBytes;
  final int? receivedBytes;
  final String? errorMessage;
  final String? localPath;
  final DateTime createdAt;

  const DownloadTask({
    required this.id,
    required this.url,
    this.title,
    this.author,
    this.platform,
    this.thumbnailUrl,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.speedBytesPerSec,
    this.totalBytes,
    this.receivedBytes,
    this.errorMessage,
    this.localPath,
    required this.createdAt,
  });

  DownloadTask copyWith({
    String? id,
    String? url,
    String? title,
    String? author,
    String? platform,
    String? thumbnailUrl,
    DownloadStatus? status,
    double? progress,
    int? speedBytesPerSec,
    int? totalBytes,
    int? receivedBytes,
    String? errorMessage,
    String? localPath,
    DateTime? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      author: author ?? this.author,
      platform: platform ?? this.platform,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      localPath: localPath ?? this.localPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
