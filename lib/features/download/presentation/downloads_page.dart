import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clip_vault/core/utils/format_utils.dart';
import 'package:clip_vault/features/download/download_controller.dart';
import 'package:clip_vault/features/download/domain/download_task.dart';

/// 下载队列页面
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadControllerProvider);
    final controller = ref.read(downloadControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载队列'),
        actions: [
          if (state.tasks.any((t) => t.status == DownloadStatus.completed))
            TextButton(
              onPressed: controller.clearCompleted,
              child: const Text('清除已完成'),
            ),
        ],
      ),
      body: state.tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_done_rounded,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    '暂无下载任务',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.tasks.length,
              itemBuilder: (context, index) {
                final task = state.tasks[index];
                return _buildTaskCard(context, ref, task);
              },
            ),
    );
  }

  Widget _buildTaskCard(BuildContext context, WidgetRef ref, DownloadTask task) {
    final controller = ref.read(downloadControllerProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _statusIcon(task.status),
                  color: _statusColor(context, task.status),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.title ?? task.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => controller.removeTask(task.id),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 进度条
            if (task.status == DownloadStatus.downloading) ...[
              LinearProgressIndicator(value: task.progress),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (task.speedBytesPerSec != null)
                    Text(
                      FormatUtils.formatSpeed(task.speedBytesPerSec!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (task.totalBytes != null)
                    Text(
                      '${FormatUtils.formatFileSize(task.receivedBytes ?? 0)} / '
                      '${FormatUtils.formatFileSize(task.totalBytes!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ],
            // 错误信息
            if (task.status == DownloadStatus.failed &&
                task.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                ),
              ),
            // 状态文字
            if (task.status == DownloadStatus.completed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '下载完成',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            if (task.status == DownloadStatus.pending)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '等待中...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(DownloadStatus status) {
    return switch (status) {
      DownloadStatus.pending => Icons.schedule_rounded,
      DownloadStatus.downloading => Icons.downloading_rounded,
      DownloadStatus.paused => Icons.pause_circle_outline_rounded,
      DownloadStatus.completed => Icons.check_circle_rounded,
      DownloadStatus.failed => Icons.error_outline_rounded,
    };
  }

  Color _statusColor(BuildContext context, DownloadStatus status) {
    return switch (status) {
      DownloadStatus.pending => Theme.of(context).colorScheme.outline,
      DownloadStatus.downloading => Theme.of(context).colorScheme.primary,
      DownloadStatus.paused => Colors.orange,
      DownloadStatus.completed => Colors.green,
      DownloadStatus.failed => Theme.of(context).colorScheme.error,
    };
  }
}
