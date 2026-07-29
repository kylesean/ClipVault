import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:clip_vault/core/utils/format_utils.dart';
import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:clip_vault/features/library/library_controller.dart';
import 'package:clip_vault/shared/services/database.dart';

/// 资源库页面 - 视频管理
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: state.isSelecting
            ? Text('已选 ${state.selectedIds.length} 项')
            : const Text('资源库'),
        leading: state.isSelecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: controller.exitSelectMode,
              )
            : null,
        actions: [
          if (state.isSelecting) ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              onPressed: controller.selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ] else ...[
            // 搜索
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => _showSearch(context, ref),
            ),
            // 视图切换
            IconButton(
              icon: Icon(state.filter.isGridView
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded),
              onPressed: controller.toggleViewMode,
            ),
            // 筛选/排序
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value.startsWith('sort:')) {
                  final sort = LibrarySort.values.firstWhere(
                    (s) => s.name == value.substring(5),
                  );
                  controller.setFilter(state.filter.copyWith(sortBy: sort));
                } else if (value.startsWith('platform:')) {
                  controller.setPlatformFilter(value.substring(9));
                } else if (value == 'platform:all') {
                  controller.setPlatformFilter(null);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'sort:time',
                  child: Text('按时间排序'),
                ),
                const PopupMenuItem(
                  value: 'sort:size',
                  child: Text('按大小排序'),
                ),
                const PopupMenuItem(
                  value: 'sort:platform',
                  child: Text('按平台排序'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'platform:all',
                  child: Text('全部平台'),
                ),
                const PopupMenuItem(
                  value: 'platform:douyin',
                  child: Text('抖音'),
                ),
                const PopupMenuItem(
                  value: 'platform:bilibili',
                  child: Text('B站'),
                ),
                const PopupMenuItem(
                  value: 'platform:kuaishou',
                  child: Text('快手'),
                ),
                const PopupMenuItem(
                  value: 'platform:xiaohongshu',
                  child: Text('小红书'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.filteredVideos.isEmpty
              ? _buildEmpty(context)
              : state.filter.isGridView
                  ? _buildGrid(context, ref, state)
                  : _buildList(context, ref, state),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            '暂无视频',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '从首页粘贴链接开始下载',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, LibraryState state) {
    final videos = state.filteredVideos;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final isSelected = state.selectedIds.contains(video.id);

        return Card(
          child: ListTile(
            leading: state.isSelecting
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => ref
                        .read(libraryControllerProvider.notifier)
                        .toggleSelection(video.id),
                  )
                : _buildThumbnail(context, video),
            title: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${UrlUtils.platformDisplayName(video.platform)} · '
              '${FormatUtils.formatDuration(video.durationSeconds)} · '
              '${FormatUtils.formatFileSize(video.fileSizeBytes)}\n'
              '${FormatUtils.formatDate(video.downloadedAt)}',
              maxLines: 2,
            ),
            trailing: state.isSelecting
                ? null
                : const Icon(Icons.chevron_right_rounded),
            onTap: () {
              if (state.isSelecting) {
                ref
                    .read(libraryControllerProvider.notifier)
                    .toggleSelection(video.id);
              } else {
                context.push('/video/${video.id}');
              }
            },
            onLongPress: () {
              if (!state.isSelecting) {
                ref.read(libraryControllerProvider.notifier).enterSelectMode();
                ref
                    .read(libraryControllerProvider.notifier)
                    .toggleSelection(video.id);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref, LibraryState state) {
    final videos = state.filteredVideos;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final isSelected = state.selectedIds.contains(video.id);

        return GestureDetector(
          onTap: () {
            if (state.isSelecting) {
              ref
                  .read(libraryControllerProvider.notifier)
                  .toggleSelection(video.id);
            } else {
              context.push('/video/${video.id}');
            }
          },
          onLongPress: () {
            if (!state.isSelecting) {
              ref.read(libraryControllerProvider.notifier).enterSelectMode();
              ref
                  .read(libraryControllerProvider.notifier)
                  .toggleSelection(video.id);
            }
          },
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      video.thumbnailPath != null
                          ? Image.file(
                              File(video.thumbnailPath!),
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.movie_rounded, size: 40),
                            ),
                      // 时长标签
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            FormatUtils.formatDuration(video.durationSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      // 选中指示
                      if (state.isSelecting)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(BuildContext context, Video video) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: video.thumbnailPath != null
            ? Image.file(File(video.thumbnailPath!), fit: BoxFit.cover)
            : Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.movie_rounded),
              ),
      ),
    );
  }

  void _showSearch(BuildContext context, WidgetRef ref) {
    showSearch(
      context: context,
      delegate: _VideoSearchDelegate(ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final state = ref.read(libraryControllerProvider);
    final count = state.selectedIds.length;
    final totalSize = state.videos
        .where((v) => state.selectedIds.contains(v.id))
        .fold<int>(0, (sum, v) => sum + v.fileSizeBytes);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定删除 $count 个视频？\n将释放 ${FormatUtils.formatFileSize(totalSize)} 空间',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(libraryControllerProvider.notifier).deleteSelected();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $count 个视频')),
        );
      }
    }
  }
}

/// 搜索代理
class _VideoSearchDelegate extends SearchDelegate<String?> {
  final WidgetRef ref;

  _VideoSearchDelegate(this.ref);

  @override
  String get searchFieldLabel => '搜索视频标题...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    ref.read(libraryControllerProvider.notifier).setSearchQuery(query);
    close(context, null);
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return const SizedBox.shrink();
  }
}
