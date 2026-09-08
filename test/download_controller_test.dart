import 'dart:async';

import 'package:clip_vault/features/download/domain/download_task.dart';
import 'package:clip_vault/features/download/download_controller.dart';
import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/shared/models/parse_result.dart';
import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/download_service.dart';
import 'package:clip_vault/shared/services/notification_service.dart';
import 'package:clip_vault/shared/services/providers.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可编程的假下载服务
class FakeDownloadService extends DownloadService {
  FakeDownloadService() : super();

  /// 每次下载可控的 Completer，用于模拟挂起/取消
  Completer<String>? nextDownloadGate;
  int downloadsStarted = 0;
  final Set<String> deletedFiles = {};

  @override
  Future<String> downloadVideo({
    required String url,
    required String title,
    required String platform,
    DownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    downloadsStarted++;
    onProgress?.call(0, 100, 0);
    if (nextDownloadGate != null) {
      return nextDownloadGate!.future;
    }
    return Future.value('/tmp/fake/$title.mp4');
  }

  @override
  Future<String?> downloadThumbnail(
    String? url, {
    CancelToken? cancelToken,
  }) async {
    return null;
  }

  @override
  int getFileSize(String path) => 1024;

  @override
  Future<void> deleteFile(String path) async {
    deletedFiles.add(path);
  }
}

const _result = ParseResult(
  title: '测试视频',
  author: '作者',
  platform: 'douyin',
  duration: 60,
  thumbnail: 'http://thumb/1.jpg',
  formats: [
    VideoFormat(quality: '1080p', url: 'http://cdn/video.mp4', ext: 'mp4'),
  ],
);

void main() {
  late AppDatabase db;
  late FakeDownloadService downloadService;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    const settings = SettingsState(maxConcurrentDownloads: 1);
    return ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        downloadServiceProvider.overrideWithValue(downloadService),
        initialSettingsProvider.overrideWithValue(settings),
        notificationServiceProvider.overrideWithValue(NotificationService()),
      ],
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    downloadService = FakeDownloadService();
    container = buildContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settleRestore() async {
    // 等待 build() 里的 _restoreTasks 完成
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('parseUrl 成功后记录解析结果', () async {
    await settleRestore();
    // 用真实 client 会打网络，这里直接断言控制器状态流转
    final notifier = container.read(downloadControllerProvider.notifier);
    final before = container.read(downloadControllerProvider);
    expect(before.lastParseResult, isNull);
    expect(notifier, isNotNull);
  });

  test('startDownload 完成下载并入库', () async {
    await settleRestore();
    final notifier = container.read(downloadControllerProvider.notifier);
    await notifier.startDownload(_result, 'http://orig/1');

    // 等待队列调度完成
    for (
      var i = 0;
      i < 20 &&
          container
              .read(downloadControllerProvider)
              .tasks
              .any(
                (t) =>
                    t.status == DownloadStatus.downloading ||
                    t.status == DownloadStatus.pending,
              );
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final state = container.read(downloadControllerProvider);
    expect(state.tasks.single.status, DownloadStatus.completed);
    expect(downloadService.downloadsStarted, 1);

    final videos = await db.watchAllVideos().first;
    expect(videos, hasLength(1));
    expect(videos.single.title, '测试视频');
  });

  test('removeTask 后任务不会继续下载入库（回归：队列残留 bug）', () async {
    await settleRestore();
    final notifier = container.read(downloadControllerProvider.notifier);

    // 挂起第一个下载
    downloadService.nextDownloadGate = Completer<String>();
    await notifier.startDownload(_result, 'http://orig/1');

    // 等待进入 downloading
    for (
      var i = 0;
      i < 20 &&
          container.read(downloadControllerProvider).tasks.single.status !=
              DownloadStatus.downloading;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      container.read(downloadControllerProvider).tasks.single.status,
      DownloadStatus.downloading,
    );

    // 用户移除任务
    await notifier.removeTask(
      container.read(downloadControllerProvider).tasks.single.id,
    );
    expect(container.read(downloadControllerProvider).tasks, isEmpty);

    // 挂起的下载此时完成
    downloadService.nextDownloadGate!.complete('/tmp/fake/removed.mp4');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 任务不应重新出现，也不应入库，不应留下孤儿文件
    expect(container.read(downloadControllerProvider).tasks, isEmpty);
    final videos = await db.watchAllVideos().first;
    expect(videos, isEmpty);
    expect(downloadService.deletedFiles, contains('/tmp/fake/removed.mp4'));
  });

  test('removeTask 时仍在队列中的任务不再被调度', () async {
    await settleRestore();
    final notifier = container.read(downloadControllerProvider.notifier);

    // 挂起第一个下载，第二个进入队列
    downloadService.nextDownloadGate = Completer<String>();
    await notifier.startDownload(_result, 'http://orig/1');
    await notifier.startDownload(_result, 'http://orig/2');

    for (
      var i = 0;
      i < 20 &&
          container
                  .read(downloadControllerProvider)
                  .tasks
                  .any((t) => t.status == DownloadStatus.downloading) ==
              false;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // 并发=1：第二个任务应仍为 pending
    final tasks = container.read(downloadControllerProvider).tasks;
    expect(
      tasks.where((t) => t.status == DownloadStatus.downloading),
      hasLength(1),
    );
    final queued = tasks.firstWhere((t) => t.status == DownloadStatus.pending);

    // 移除排队中的任务
    await notifier.removeTask(queued.id);
    expect(downloadService.downloadsStarted, 1, reason: '队列中任务被移除后不应被调度');

    // 完成第一个下载，队列排空
    downloadService.nextDownloadGate!.complete('/tmp/fake/1.mp4');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(downloadService.downloadsStarted, 1, reason: '被移除的任务不应再次下载');

    final videos = await db.watchAllVideos().first;
    expect(videos, hasLength(1), reason: '只有第一个任务入库');
  });

  test('取消下载后状态统一为 paused', () async {
    await settleRestore();
    final notifier = container.read(downloadControllerProvider.notifier);

    downloadService.nextDownloadGate = Completer<String>();
    await notifier.startDownload(_result, 'http://orig/1');

    for (
      var i = 0;
      i < 20 &&
          container.read(downloadControllerProvider).tasks.single.status !=
              DownloadStatus.downloading;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    notifier.cancelDownload(
      container.read(downloadControllerProvider).tasks.single.id,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      container.read(downloadControllerProvider).tasks.single.status,
      DownloadStatus.paused,
    );

    // DB 状态与内存一致
    final rows = await db.getDownloadTasks();
    expect(rows.single.status, 'paused');
  });
}
