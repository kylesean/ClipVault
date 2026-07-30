import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:clip_vault/core/constants/app_constants.dart';

/// 下载进度回调
typedef DownloadProgressCallback = void Function(
  int receivedBytes,
  int totalBytes,
  int speedBytesPerSec,
);

/// 视频文件下载服务
class DownloadService {
  final Dio _dio = Dio(BaseOptions(
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    },
    followRedirects: true,
  ));
  final _uuid = const Uuid();

  /// 根据平台名称返回对应的 Referer（绕过 CDN 防盗链）
  static String _refererForPlatform(String platform) {
    return switch (platform) {
      'douyin' => 'https://www.douyin.com/',
      'tiktok' => 'https://www.tiktok.com/',
      'bilibili' => 'https://www.bilibili.com/',
      'youtube' => 'https://www.youtube.com/',
      'instagram' => 'https://www.instagram.com/',
      _ => '',
    };
  }

  /// 获取视频存储目录
  Future<Directory> getVideoDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory(p.join(dir.path, 'videos'));
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    return videoDir;
  }

  /// 获取缩略图存储目录
  Future<Directory> getThumbnailDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(dir.path, 'thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    return thumbDir;
  }

  /// 下载视频文件
  /// 返回本地文件路径
  Future<String> downloadVideo({
    required String url,
    required String title,
    required String platform,
    DownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final videoDir = await getVideoDirectory();
    final fileName = _generateFileName(title);
    final filePath = p.join(videoDir.path, fileName);

    // 根据解析出的平台设置 Referer
    final referer = _refererForPlatform(platform);

    int lastTick = DateTime.now().millisecondsSinceEpoch;
    int lastBytes = 0;

    await _dio.download(
      url,
      filePath,
      cancelToken: cancelToken,
      options: referer.isNotEmpty
          ? Options(headers: {'Referer': referer})
          : null,
      onReceiveProgress: (received, total) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - lastTick;

        int speed = 0;
        if (elapsed >= 500) {
          speed = ((received - lastBytes) * 1000 ~/ elapsed);
          lastTick = now;
          lastBytes = received;
        }

        onProgress?.call(received, total, speed);
      },
    );

    return filePath;
  }

  /// 下载缩略图
  Future<String?> downloadThumbnail(String? url) async {
    if (url == null || url.isEmpty) return null;

    try {
      final thumbDir = await getThumbnailDirectory();
      final fileName = '${_uuid.v4()}${AppConstants.thumbnailExtension}';
      final filePath = p.join(thumbDir.path, fileName);

      await _dio.download(url, filePath);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// 删除本地文件
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 获取文件大小
  Future<int> getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  String _generateFileName(String title) {
    final sanitized = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final shortTitle = sanitized.length > 50
        ? sanitized.substring(0, 50)
        : sanitized;
    final id = _uuid.v4().substring(0, 8);
    return '${shortTitle}_$id${AppConstants.videoExtension}';
  }
}
