import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:clip_vault/features/download/domain/download_task.dart';
import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/shared/models/parse_result.dart';
import 'package:clip_vault/shared/services/database.dart' hide DownloadTask, DownloadTasks;
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

  DownloadQueueState copyWith({
    List<DownloadTask>? tasks,
    bool? isParsing,
    String? parseError,
    ParseResult? lastParseResult,
    String? lastParsedUrl,
  }) {
    return DownloadQueueState(
      tasks: tasks ?? this.tasks,
      isParsing: isParsing ?? this.isParsing,
      parseError: parseError,
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
  final _pendingQueue = Queue<({DownloadTask task, ParseResult result, String originalUrl})>();
  bool _isProcessingQueue = false;

  @override
  DownloadQueueState build() => const DownloadQueueState();

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
      state = state.copyWith(
        isParsing: false,
        parseError: e.toString(),
      );
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

    // 持久化到数据库
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

    // 加入队列，由调度器统一管控并发
    _pendingQueue.add((task: task, result: result, originalUrl: originalUrl));
    _processQueue();
  }

  /// 队列调度器：尊重最大并发数设置
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_pendingQueue.isNotEmpty) {
        final maxConcurrent =
            ref.read(settingsControllerProvider).maxConcurrentDownloads;

        if (state.activeDownloads >= maxConcurrent) {
          // 等待任一下载完成后再继续
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final item = _pendingQueue.removeFirst();
        _updateTask(item.task.id, (t) => t.copyWith(
          status: DownloadStatus.downloading,
        ));
        await _updateDbStatus(item.task.id, 'downloading');

        // 不 await，并发执行
        _executeDownload(item.task, item.result, item.originalUrl);
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
          _updateTask(task.id, (t) => t.copyWith(
            progress: progress,
            receivedBytes: received,
            totalBytes: total > 0 ? total : null,
            speedBytesPerSec: speed,
          ));
        },
      );

      // 下载缩略图
      final thumbnailPath =
          await downloadService.downloadThumbnail(result.thumbnail);
      final fileSize = await downloadService.getFileSize(localPath);

      // 入库
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

      // 更新任务状态
      _updateTask(task.id, (t) => t.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: localPath,
      ));
      await _updateDbStatus(task.id, 'completed');
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        _updateTask(task.id, (t) => t.copyWith(status: DownloadStatus.paused));
        await _updateDbStatus(task.id, 'paused');
      } else {
        _updateTask(task.id, (t) => t.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ));
        await _updateDbStatus(task.id, 'failed');
      }
    } finally {
      _cancelTokens.remove(task.id);
      // 下载完成后触发队列继续
      _processQueue();
    }
  }

  /// 取消下载
  void cancelDownload(String taskId) {
    _cancelTokens[taskId]?.cancel('用户取消');
    _updateTask(taskId, (t) => t.copyWith(status: DownloadStatus.pending));
  }

  /// 移除任务
  void removeTask(String taskId) {
    cancelDownload(taskId);
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );
  }

  /// 清除已完成任务
  void clearCompleted() {
    state = state.copyWith(
      tasks: state.tasks
          .where((t) => t.status != DownloadStatus.completed)
          .toList(),
    );
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
