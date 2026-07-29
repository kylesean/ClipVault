import 'dart:io';

import 'package:clip_vault/core/utils/format_utils.dart';
import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:clip_vault/features/download/download_controller.dart';
import 'package:clip_vault/features/download/domain/download_task.dart';
import 'package:clip_vault/features/library/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 首页 - 快捷下载入口 + 最近下载
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _urlController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSubmitUrl() {
    final text = _urlController.text.trim();
    if (text.isEmpty) return;

    final url = UrlUtils.extractUrl(text);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到有效链接')),
      );
      return;
    }

    ref.read(downloadControllerProvider.notifier).parseUrl(url);
    _urlController.clear();
    _focusNode.unfocus();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      _onSubmitUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(downloadControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipVault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () => context.push('/downloads'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 链接输入区域
            _buildInputSection(),
            const SizedBox(height: 16),

            // 解析状态
            if (downloadState.isParsing) _buildParsingIndicator(),
            if (downloadState.parseError != null)
              _buildParseError(downloadState.parseError!),
            if (downloadState.lastParseResult != null)
              _buildParseResultCard(downloadState),

            const SizedBox(height: 24),

            // 活跃下载
            if (downloadState.tasks
                .where((t) =>
                    t.status == DownloadStatus.downloading ||
                    t.status == DownloadStatus.pending)
                .isNotEmpty) ...[
              _buildSectionHeader('下载中'),
              const SizedBox(height: 8),
              ...downloadState.tasks
                  .where((t) =>
                      t.status == DownloadStatus.downloading ||
                      t.status == DownloadStatus.pending)
                  .map((t) => _buildDownloadTile(t)),
              const SizedBox(height: 24),
            ],

            // 最近下载
            _buildSectionHeader('最近下载'),
            const SizedBox(height: 8),
            _buildRecentVideos(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '粘贴视频链接',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '粘贴抖音、B站、快手等视频链接...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded),
                  onPressed: _pasteFromClipboard,
                ),
              ),
              onSubmitted: (_) => _onSubmitUrl(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _onSubmitUrl,
              icon: const Icon(Icons.search_rounded),
              label: const Text('解析并下载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParsingIndicator() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在解析链接...'),
          ],
        ),
      ),
    );
  }

  Widget _buildParseError(String error) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(error)),
          ],
        ),
      ),
    );
  }

  Widget _buildParseResultCard(DownloadQueueState state) {
    final result = state.lastParseResult!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(UrlUtils.platformDisplayName(result.platform)),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (result.duration > 0)
                  Text(
                    FormatUtils.formatDuration(result.duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.title,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              result.author,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                ref
                    .read(downloadControllerProvider.notifier)
                    .startDownload(result, state.lastParsedUrl ?? '');
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('开始下载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }

  Widget _buildDownloadTile(DownloadTask task) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.downloading_rounded),
        title: Text(
          task.title ?? '下载中...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: task.status == DownloadStatus.downloading
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: task.progress),
                  const SizedBox(height: 4),
                  Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%'
                    '${task.speedBytesPerSec != null ? ' · ${FormatUtils.formatSpeed(task.speedBytesPerSec!)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              )
            : const Text('等待中...'),
        trailing: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => ref
              .read(downloadControllerProvider.notifier)
              .cancelDownload(task.id),
        ),
      ),
    );
  }

  Widget _buildRecentVideos() {
    final libraryState = ref.watch(libraryControllerProvider);
    final videos = libraryState.videos;

    if (videos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.video_library_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                '还没有下载的视频',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final recentVideos = videos.take(5).toList();
    return Column(
      children: recentVideos.map((video) {
        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: video.thumbnailPath != null
                    ? Image.file(
                        File(video.thumbnailPath!),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie_rounded),
                      ),
              ),
            ),
            title: Text(
              video.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${UrlUtils.platformDisplayName(video.platform)} · '
              '${FormatUtils.formatFileSize(video.fileSizeBytes)} · '
              '${FormatUtils.formatDate(video.downloadedAt)}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/video/${video.id}'),
          ),
        );
      }).toList(),
    );
  }
}
