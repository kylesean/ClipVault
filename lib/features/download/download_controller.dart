import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:clip_vault/features/download/domain/download_task.dart';
import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/shared/models/parse_result.dart';
import 'package:clip_vault/shared/services/database.dart'
    hide DownloadTask, DownloadTasks;
import 'package:clip_vault/shared/services/notification_service.dart';
import 'package:clip_vault/shared/services/providers.dart';

/// 下载队列状态
class DownloadQueueState {
  final List<DownloadTask> tasks;
  final bool isParsing;
  final String? parseError;
  final ParseResult? lastParseResult;
  final String? lastParsedUrl;

  const DownloadQueueState({
    this.tasks = const [],
    this.isParsing = false,
    this.parseError,
    this.lastParseResult,
    this.lastParsedUrl,
  });

  /// 哨兵：区分「未提供」与「显式清除」
  static const Object _unset = Object();

  DownloadQueueState copyWith({
    List<DownloadTask>? tasks,
    bool? isParsing,
    Object? parseError = _unset,
    ParseResult? lastParseResult,
    String? lastParsedUrl,
  }) {
    return DownloadQueueState(
      tasks: tasks ?? this.tasks,
      isParsing: isParsing ?? this.isParsing,
      parseError: identical(parseError, _unset)
          ? this.parseError
          : parseError as String?,
      lastParseResult: lastParseResult ?? this.lastParseResult,
      lastParsedUrl: lastParsedUrl ?? this.lastParsedUrl,
    );
  }

  /// 活跃下载数
  int get activeDownloads =>
      tasks.where((t) => t.status == DownloadStatus.downloading).length;
}

/// 下载控制器（现代 Notifier 模式）
class DownloadController extends Notifier<DownloadQueueState> {
  final Map<String, CancelToken> _cancelTokens = {};
  final _uuid = const Uuid();
  final _pendingQueue =
      Queue<({DownloadTask task, ParseResult result, String originalUrl})>();
  bool _isProcessingQueue = false;

  @override
  DownloadQueueState build() {
    // 启动时从数据库恢复历史任务（挂起/失败/已完成）
    _restoreTasks();
    return const DownloadQueueState();
  }

  /// 从数据库恢复历史任务（只读一次，避免与实时进度更新冲突）
  void _restoreTasks() {
    final db = ref.read(databaseProvider);
    Future(() async {
      final rows = await db.getDownloadTasks();
      if (rows.isEmpty) return;
      final restored = rows
          .map(
            (row) => DownloadTask(
              id: row.id,
              url: row.url,
              title: row.title,
              author: row.author,
              platform: row.platform,
              thumbnailUrl: row.thumbnailUrl,
              status: _statusFromDb(row.status),
              progress: row.progress,
              totalBytes: row.totalBytes,
              receivedBytes: row.receivedBytes,
              errorMessage: row.errorMessage,
              localPath: row.localPath,
              createdAt: row.createdAt,
            ),
          )
          .toList();
      state = state.copyWith(tasks: restored);

      // 中断的下载（应用被杀/崩溃）标记为 paused，保持状态诚实
      for (final row in rows.where((r) => r.status == 'downloading')) {
        unawaited(
          db.updateDownloadTask(
            row.id,
            const DownloadTasksCompanion(status: drift.Value('paused')),
          ),
        );
      }
    });
  }

  DownloadStatus _statusFromDb(String status) {
    return switch (status) {
      'pending' => DownloadStatus.pending,
      'downloading' => DownloadStatus.paused,
      'paused' => DownloadStatus.paused,
      'completed' => DownloadStatus.completed,
      _ => DownloadStatus.failed,
    };
  }

  /// 解析链接
  Future<void> parseUrl(String url) async {
    state = state.copyWith(isParsing: true, parseError: null);

    try {
      final client = ref.read(parseApiClientProvider);
      final result = await client.parseUrl(url);
      state = state.copyWith(
        isParsing: false,
        lastParseResult: result,
        lastParsedUrl: url,
      );
    } catch (e) {
      state = state.copyWith(isParsing: false, parseError: e.toString());
    }
  }

  /// 开始下载（从解析结果）
  Future<void> startDownload(ParseResult result, String originalUrl) async {
    final format = result.bestFormat;
    if (format == null) return;

    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      url: format.url,
      title: result.title,
      author: result.author,
      platform: result.platform,
      thumbnailUrl: result.thumbnail,
      status: DownloadStatus.pending,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(tasks: [task, ...state.tasks]);

    // 持久化到数据库（失败不阻塞内存队列，仅标记失败）
    try {
      final db = ref.read(databaseProvider);
      await db.insertDownloadTask(
        DownloadTasksCompanion(
          id: drift.Value(taskId),
          url: drift.Value(format.url),
          title: drift.Value(result.title),
          author: drift.Value(result.author),
          platform: drift.Value(result.platform),
          thumbnailUrl: drift.Value(result.thumbnail),
          status: const drift.Value('pending'),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
    } catch (e) {
      _updateTask(
        taskId,
        (t) => t.copyWith(
          status: DownloadStatus.failed,
          errorMessage: '任务保存失败: $e',
        ),
      );
      return;
    }

    // 加入队列，由调度器统一管控并发
    _pendingQueue.add((task: task, result: result, originalUrl: originalUrl));
    unawaited(_processQueue());
  }

  /// 重试失败/暂停的任务
  Future<void> retryTask(String taskId) async {
    final task = state.tasks.firstWhereOrNull((t) => t.id == taskId);
    if (task == null ||
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.pending) {
      return;
    }

    final retried = task.copyWith(
      status: DownloadStatus.pending,
      errorMessage: null,
      progress: 0,
      receivedBytes: null,
      totalBytes: null,
    );
    _updateTask(taskId, (t) => retried);
    await _updateDbStatus(taskId, 'pending');

    final result = ParseResult(
      title: task.title ?? '未知标题',
      author: task.author ?? '未知作者',
      platform: task.platform ?? 'unknown',
      duration: 0,
      thumbnail: task.thumbnailUrl,
      formats: [VideoFormat(quality: 'retry', url: task.url, ext: 'mp4')],
    );
    _pendingQueue.add((task: retried, result: result, originalUrl: task.url));
    unawaited(_processQueue());
  }

  /// 队列调度器：尊重最大并发数设置
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_pendingQueue.isNotEmpty) {
        final maxConcurrent =
            (ref.read(settingsControllerProvider).maxConcurrentDownloads).clamp(
              1,
              100,
            );

        if (state.activeDownloads >= maxConcurrent) {
          // 等待任一下载完成后再继续
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final item = _pendingQueue.removeFirst();
        _updateTask(
          item.task.id,
          (t) => t.copyWith(status: DownloadStatus.downloading),
        );
        await _updateDbStatus(item.task.id, 'downloading');

        // 不 await，并发执行
        unawaited(_executeDownload(item.task, item.result, item.originalUrl));
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// 执行下载
  Future<void> _executeDownload(
    DownloadTask task,
    ParseResult result,
    String originalUrl,
  ) async {
    final downloadService = ref.read(downloadServiceProvider);
    final db = ref.read(databaseProvider);
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final localPath = await downloadService.downloadVideo(
        url: task.url,
        title: result.title,
        platform: result.platform,
        cancelToken: cancelToken,
        onProgress: (received, total, speed) {
          final progress = total > 0 ? received / total : 0.0;
          _updateTask(
            task.id,
            (t) => t.copyWith(
              progress: progress,
              receivedBytes: received,
              totalBytes: total > 0 ? total : null,
              speedBytesPerSec: speed,
            ),
          );
        },
      );

      // 下载缩略图（失败不阻断主流程，超时可取消）
      String? thumbnailPath;
      try {
        thumbnailPath = await downloadService.downloadThumbnail(
          result.thumbnail,
          cancelToken: cancelToken,
        );
      } catch (_) {
        thumbnailPath = null;
      }
      final fileSize = await downloadService.getFileSize(localPath);

      // 任务可能已被用户移除：清理文件，不入库
      if (!state.tasks.any((t) => t.id == task.id)) {
        await downloadService.deleteFile(localPath);
        if (thumbnailPath != null) {
          await downloadService.deleteFile(thumbnailPath);
        }
        return;
      }

      // 入库（失败时清理文件，避免孤儿文件）
      try {
        await db.insertVideo(
          VideosCompanion(
            id: drift.Value(task.id),
            title: drift.Value(result.title),
            author: drift.Value(result.author),
            platform: drift.Value(result.platform),
            originalUrl: drift.Value(originalUrl),
            localPath: drift.Value(localPath),
            thumbnailPath: drift.Value(thumbnailPath),
            durationSeconds: drift.Value(result.duration),
            fileSizeBytes: drift.Value(fileSize),
            downloadedAt: drift.Value(DateTime.now()),
          ),
        );
      } catch (e) {
        await downloadService.deleteFile(localPath);
        if (thumbnailPath != null) {
          await downloadService.deleteFile(thumbnailPath);
        }
        rethrow;
      }

      // 更新任务状态
      _updateTask(
        task.id,
        (t) => t.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          localPath: localPath,
        ),
      );
      await _updateDbStatus(task.id, 'completed');

      // 下载完成通知
      if (ref.read(settingsControllerProvider).downloadNotification) {
        unawaited(
          ref
              .read(notificationServiceProvider)
              .showDownloadComplete(result.title),
        );
      }
    } catch (e, st) {
      // 完整错误打到控制台（flutter run 日志），界面只展示 e.toString()
      debugPrint('ClipVault 下载失败 task=${task.id} url=${task.url}');
      debugPrint('$e');
      debugPrint('$st');
      if (e is DioException && CancelToken.isCancel(e)) {
        _updateTask(task.id, (t) => t.copyWith(status: DownloadStatus.paused));
        await _updateDbStatus(task.id, 'paused');
      } else {
        _updateTask(
          task.id,
          (t) => t.copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
          ),
        );
        await _updateDbStatus(task.id, 'failed');
      }
    } finally {
      _cancelTokens.remove(task.id);
      // 下载完成后触发队列继续
      unawaited(_processQueue());
    }
  }

  /// 取消下载（统一置为 paused，界面与数据库一致）
  void cancelDownload(String taskId) {
    _cancelTokens[taskId]?.cancel('用户取消');
    _updateTask(taskId, (t) => t.copyWith(status: DownloadStatus.paused));
    _updateDbStatus(taskId, 'paused');
  }

  /// 移除任务（同时从队列/数据库/磁盘清理）
  Future<void> removeTask(String taskId) async {
    cancelDownload(taskId);
    _pendingQueue.removeWhere((e) => e.task.id == taskId);

    final task = state.tasks.firstWhereOrNull((t) => t.id == taskId);
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );

    try {
      final downloadService = ref.read(downloadServiceProvider);
      if (task?.localPath != null && task!.localPath!.isNotEmpty) {
        await downloadService.deleteFile(task.localPath!);
      }
      final db = ref.read(databaseProvider);
      await db.deleteDownloadTask(taskId);
    } catch (e) {
      // 清理失败不影响界面状态
    }
  }

  /// 清除已完成任务（内存 + 数据库 + 无本地文件残留）
  Future<void> clearCompleted() async {
    final completedIds = state.tasks
        .where((t) => t.status == DownloadStatus.completed)
        .map((t) => t.id)
        .toList();
    state = state.copyWith(
      tasks: state.tasks
          .where((t) => t.status != DownloadStatus.completed)
          .toList(),
    );
    try {
      final db = ref.read(databaseProvider);
      for (final id in completedIds) {
        await db.deleteDownloadTask(id);
      }
    } catch (e) {
      // 清理失败不影响界面状态
    }
  }

  void _updateTask(String taskId, DownloadTask Function(DownloadTask) updater) {
    state = state.copyWith(
      tasks: state.tasks.map((t) => t.id == taskId ? updater(t) : t).toList(),
    );
  }

  Future<void> _updateDbStatus(String taskId, String status) async {
    final db = ref.read(databaseProvider);
    await db.updateDownloadTask(
      taskId,
      DownloadTasksCompanion(status: drift.Value(status)),
    );
  }
}

/// 下载控制器 Provider（现代 Notifier）
final downloadControllerProvider =
    NotifierProvider<DownloadController, DownloadQueueState>(
      DownloadController.new,
    );
