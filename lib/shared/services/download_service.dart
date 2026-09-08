import 'dart:io';

import 'package:clip_vault/core/constants/app_constants.dart';
import 'package:clip_vault/core/errors/app_exceptions.dart';
import 'package:clip_vault/features/decode/douyin_api.dart'
    show
        buildTransportCookie,
        kDouyinReferer,
        kDouyinUserAgent,
        kTikTokReferer,
        kTikTokUserAgent;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 下载进度回调
typedef DownloadProgressCallback =
    void Function(int receivedBytes, int totalBytes, int speedBytesPerSec);

/// 各平台 CDN 防盗链头（直连下载时带上，替代原来的服务端代理）。
Map<String, String> _headersForPlatform(String platform) {
  final isTikTok = platform == 'tiktok';
  return {
    'User-Agent': isTikTok ? kTikTokUserAgent : kDouyinUserAgent,
    'Referer': isTikTok ? kTikTokReferer : kDouyinReferer,
  };
}

/// 分段下载阈值：小于它单连接直下（分片反而更慢）
const int _segmentThresholdBytes = 8 * 1024 * 1024;

/// 分段目标大小：每连接约 8MB，连接数封顶 8
const int _bytesPerConnection = 8 * 1024 * 1024;
const int _maxConnections = 8;

/// 分片区间计算（纯函数）：返回 [start, end] 闭区间，保证无缝无重叠。
@visibleForTesting
List<({int start, int end})> splitSegments(
  int totalBytes, {
  int bytesPerConnection = _bytesPerConnection,
  int maxConnections = _maxConnections,
}) {
  if (totalBytes <= 0) return [];
  var conns = (totalBytes / bytesPerConnection).floor().clamp(1, maxConnections);
  if (conns < 2) return [(start: 0, end: totalBytes - 1)];
  conns = conns.clamp(2, maxConnections);
  final base = totalBytes ~/ conns;
  final out = <({int start, int end})>[];
  for (var i = 0; i < conns; i++) {
    final start = i * base;
    final end = i == conns - 1 ? totalBytes - 1 : start + base - 1;
    out.add((start: start, end: end));
  }
  return out;
}

/// 视频文件下载服务（纯端直连 CDN，无服务端代理）。
class DownloadService {
  final String? _cookie;

  final Dio _dio;
  final _uuid = const Uuid();

  DownloadService({String? cookie})
    : _cookie = cookie, // ignore: prefer_initializing_formals – 私有命名形参无法跨库传递，保留初始化列表
      _dio = Dio(
        BaseOptions(
          followRedirects: true,
          maxRedirects: 5,
          // 建连超时保留；视频体不设 receiveTimeout（大文件必超时，P0 修）。
          connectTimeout: const Duration(seconds: 15),
        ),
      );

  /// 归一化并校验 CDN 直链，非法直接抛中文错，
  /// 避免坏 URL 流进 Dio 包成不知所云的 unknown 错误。
  static String _normalizeDirectUrl(String url) {
    var normalized = url.trim();
    // 协议相对 URL（//host/path）补 https
    if (normalized.startsWith('//')) normalized = 'https:$normalized';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw DownloadException('视频直链无效，请重新解析（$url）');
    }
    return normalized;
  }

  /// 获取视频存储目录
  Future<Directory> getVideoDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory(p.join(dir.path, 'videos'));
    if (!videoDir.existsSync()) {
      videoDir.createSync(recursive: true);
    }
    return videoDir;
  }

  /// 获取缩略图存储目录
  Future<Directory> getThumbnailDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(dir.path, 'thumbnails'));
    if (!thumbDir.existsSync()) {
      thumbDir.createSync(recursive: true);
    }
    return thumbDir;
  }

  /// 直连 CDN 下载视频文件，返回本地文件路径。
  ///
  /// 大文件（≥8MB）且 CDN 支持 Range 时多连接分段并下
  /// （CDN 常对单连接限速）；否则单连接直下。分段失败自动回退单连接。
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

    // 先归一化校验，直链有问题直接报中文，不进 Dio
    final directUrl = _normalizeDirectUrl(url);

    final headers = _headersForPlatform(platform);
    // 必须归一化+消毒：原文可能是多行 cookies.txt，直接塞进 Header
    // 会抛 FormatException: Invalid HTTP header field value
    final cookie = buildTransportCookie(_cookie);
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    // 探测分段条件（失败/不支持就当没这回事，走单连接）
    final total = await _probeContentLength(directUrl, headers);
    if (total != null && total >= _segmentThresholdBytes) {
      try {
        return await _downloadSegmented(
          url: directUrl,
          filePath: filePath,
          headers: headers,
          totalBytes: total,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } catch (e) {
        // 用户取消不回退，直接抛；其他错误清场后回退单连接再试一次
        if (cancelToken?.isCancelled == true) rethrow;
        debugPrint('ClipVault 分段下载失败，回退单连接：$e');
      }
    }

    return _downloadSingle(
      url: directUrl,
      filePath: filePath,
      headers: headers,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// HEAD 探测文件大小 + Range 支持。任一不满足返回 null（走单连接）。
  Future<int?> _probeContentLength(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final resp = await _dio
          .head<dynamic>(url, options: Options(headers: headers))
          .timeout(const Duration(seconds: 10));
      final total = int.tryParse(resp.headers.value('content-length') ?? '');
      final ranges = (resp.headers.value('accept-ranges') ?? '')
          .toLowerCase()
          .contains('bytes');
      if (total != null && total > 0 && ranges) return total;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 单连接下载（原逻辑）。
  Future<String> _downloadSingle({
    required String url,
    required String filePath,
    required Map<String, String> headers,
    required DownloadProgressCallback? onProgress,
    required CancelToken? cancelToken,
  }) async {
    var lastTick = DateTime.now().millisecondsSinceEpoch;
    var lastBytes = 0;
    var currentSpeed = 0;

    await _dio.download(
      url,
      filePath,
      cancelToken: cancelToken,
      options: Options(headers: headers),
      onReceiveProgress: (received, total) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - lastTick;

        if (elapsed >= 500) {
          currentSpeed = ((received - lastBytes) * 1000 ~/ elapsed);
          lastTick = now;
          lastBytes = received;
        }

        onProgress?.call(received, total, currentSpeed);
      },
    );

    return filePath;
  }

  /// 多连接分段下载：N 个 Range 并发，最后按序合并。
  Future<String> _downloadSegmented({
    required String url,
    required String filePath,
    required Map<String, String> headers,
    required int totalBytes,
    required DownloadProgressCallback? onProgress,
    required CancelToken? cancelToken,
  }) async {
    final segments = splitSegments(totalBytes);
    // 极端情况（易测分支）：分片算出来不足 2 段就单下
    if (segments.length < 2) {
      return _downloadSingle(
        url: url,
        filePath: filePath,
        headers: headers,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    final partPaths = List<String>.generate(
      segments.length,
      (i) => '$filePath.part$i',
    );
    final received = List<int>.filled(segments.length, 0);

    var lastTick = DateTime.now().millisecondsSinceEpoch;
    var lastBytes = 0;
    var currentSpeed = 0;

    void report() {
      final sum = received.fold(0, (a, b) => a + b);
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - lastTick;
      if (elapsed >= 500 || sum >= totalBytes) {
        currentSpeed = elapsed > 0 ? ((sum - lastBytes) * 1000 ~/ elapsed) : 0;
        lastTick = now;
        lastBytes = sum;
      }
      onProgress?.call(sum, totalBytes, currentSpeed);
    }

    Future<void> cleanup() async {
      for (final part in partPaths) {
        try {
          await File(part).delete();
        } catch (_) {}
      }
      try {
        await File(filePath).delete();
      } catch (_) {}
    }

    try {
      // 同一个 CancelToken 可共享给多个请求，一键全停
      await Future.wait([
        for (var i = 0; i < segments.length; i++)
          _dio.download(
            url,
            partPaths[i],
            cancelToken: cancelToken,
            options: Options(
              headers: {
                ...headers,
                'Range': 'bytes=${segments[i].start}-${segments[i].end}',
              },
            ),
            onReceiveProgress: (rec, _) {
              received[i] = rec;
              report();
            },
          ),
      ]);

      // 逐片验长（CDN 若无视 Range 会下成整文件，长度对不上）
      for (var i = 0; i < segments.length; i++) {
        final file = File(partPaths[i]);
        final expectLen = segments[i].end - segments[i].start + 1;
        if (!file.existsSync() || file.lengthSync() != expectLen) {
          throw DownloadException('分片 $i 长度不符（CDN 可能不支持分段）');
        }
      }

      await mergeParts(partPaths, filePath);
      onProgress?.call(totalBytes, totalBytes, currentSpeed);
      return filePath;
    } catch (e) {
      await cleanup();
      rethrow;
    }
  }

  /// 按序合并分片（流式 1MB 搬运，内存恒定），成功后删分片。
  @visibleForTesting
  static Future<void> mergeParts(List<String> partPaths, String targetPath) async {
    final out = await File(targetPath).open(mode: FileMode.write);
    try {
      for (final part in partPaths) {
        final raf = await File(part).open();
        try {
          while (true) {
            final chunk = await raf.read(1024 * 1024);
            if (chunk.isEmpty) break;
            await out.writeFrom(chunk);
          }
        } finally {
          await raf.close();
        }
      }
    } finally {
      await out.close();
    }
    for (final part in partPaths) {
      try {
        await File(part).delete();
      } catch (_) {}
    }
  }

  /// 下载缩略图（超时/失败返回 null，不阻断主流程）
  Future<String?> downloadThumbnail(
    String? url, {
    CancelToken? cancelToken,
  }) async {
    if (url == null || url.isEmpty) return null;

    try {
      final thumbDir = await getThumbnailDirectory();
      final fileName = '${_uuid.v4()}${AppConstants.thumbnailExtension}';
      final filePath = p.join(thumbDir.path, fileName);

      await _dio
          .download(url, filePath, cancelToken: cancelToken)
          .timeout(const Duration(seconds: 15));
      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// 供测试/外部按平台取请求头
  Map<String, String> headersFor(String platform) =>
      _headersForPlatform(platform);

  /// 删除本地文件
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  /// 获取文件大小（同步 stat，小开销）
  int getFileSize(String path) {
    final file = File(path);
    if (file.existsSync()) {
      return file.lengthSync();
    }
    return 0;
  }

  String _generateFileName(String title) {
    final sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final shortTitle = sanitized.length > 50
        ? sanitized.substring(0, 50)
        : sanitized;
    final id = _uuid.v4().substring(0, 8);
    return '${shortTitle}_$id${AppConstants.videoExtension}';
  }
}
