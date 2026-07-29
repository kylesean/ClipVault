import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/providers.dart';

/// 资源库筛选条件
enum LibrarySort { time, size, platform }

class LibraryFilter {
  final String? platform;
  final LibrarySort sortBy;
  final bool isGridView;
  final String searchQuery;

  const LibraryFilter({
    this.platform,
    this.sortBy = LibrarySort.time,
    this.isGridView = false,
    this.searchQuery = '',
  });

  LibraryFilter copyWith({
    String? platform,
    LibrarySort? sortBy,
    bool? isGridView,
    String? searchQuery,
    bool clearPlatform = false,
  }) {
    return LibraryFilter(
      platform: clearPlatform ? null : (platform ?? this.platform),
      sortBy: sortBy ?? this.sortBy,
      isGridView: isGridView ?? this.isGridView,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// 资源库状态
class LibraryState {
  final List<Video> videos;
  final LibraryFilter filter;
  final bool isLoading;
  final Set<String> selectedIds;
  final bool isSelecting;

  const LibraryState({
    this.videos = const [],
    this.filter = const LibraryFilter(),
    this.isLoading = true,
    this.selectedIds = const {},
    this.isSelecting = false,
  });

  LibraryState copyWith({
    List<Video>? videos,
    LibraryFilter? filter,
    bool? isLoading,
    Set<String>? selectedIds,
    bool? isSelecting,
  }) {
    return LibraryState(
      videos: videos ?? this.videos,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      selectedIds: selectedIds ?? this.selectedIds,
      isSelecting: isSelecting ?? this.isSelecting,
    );
  }

  /// 经过筛选和排序后的视频列表
  List<Video> get filteredVideos {
    var result = List<Video>.from(videos);

    // 平台筛选
    if (filter.platform != null) {
      result = result.where((v) => v.platform == filter.platform).toList();
    }

    // 搜索
    if (filter.searchQuery.isNotEmpty) {
      final q = filter.searchQuery.toLowerCase();
      result = result
          .where((v) =>
              v.title.toLowerCase().contains(q) ||
              v.author.toLowerCase().contains(q))
          .toList();
    }

    // 排序
    switch (filter.sortBy) {
      case LibrarySort.time:
        result.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      case LibrarySort.size:
        result.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
      case LibrarySort.platform:
        result.sort((a, b) => a.platform.compareTo(b.platform));
    }

    return result;
  }
}

/// 资源库控制器（现代 Notifier 模式）
class LibraryController extends Notifier<LibraryState> {
  StreamSubscription<List<Video>>? _videoSub;

  @override
  LibraryState build() {
    _loadVideos();
    ref.onDispose(() => _videoSub?.cancel());
    return const LibraryState();
  }

  void _loadVideos() {
    final db = ref.read(databaseProvider);
    _videoSub = db.watchAllVideos().listen((videos) {
      state = state.copyWith(videos: videos, isLoading: false);
    });
  }

  void setFilter(LibraryFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void toggleViewMode() {
    state = state.copyWith(
      filter: state.filter.copyWith(isGridView: !state.filter.isGridView),
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(filter: state.filter.copyWith(searchQuery: query));
  }

  void setPlatformFilter(String? platform) {
    if (platform == null) {
      state = state.copyWith(filter: state.filter.copyWith(clearPlatform: true));
    } else {
      state = state.copyWith(filter: state.filter.copyWith(platform: platform));
    }
  }

  // ===== 多选模式 =====

  void enterSelectMode() {
    state = state.copyWith(isSelecting: true, selectedIds: {});
  }

  void exitSelectMode() {
    state = state.copyWith(isSelecting: false, selectedIds: {});
  }

  void toggleSelection(String videoId) {
    final selected = Set<String>.from(state.selectedIds);
    if (selected.contains(videoId)) {
      selected.remove(videoId);
    } else {
      selected.add(videoId);
    }
    state = state.copyWith(selectedIds: selected);
  }

  void selectAll() {
    state = state.copyWith(
      selectedIds: state.filteredVideos.map((v) => v.id).toSet(),
    );
  }

  // ===== 删除 =====

  Future<void> deleteSelected() async {
    final db = ref.read(databaseProvider);
    final downloadService = ref.read(downloadServiceProvider);

    for (final id in state.selectedIds) {
      final video = state.videos.where((v) => v.id == id).firstOrNull;
      if (video != null) {
        await downloadService.deleteFile(video.localPath);
        if (video.thumbnailPath != null) {
          await downloadService.deleteFile(video.thumbnailPath!);
        }
      }
    }

    await db.deleteVideos(state.selectedIds.toList());
    exitSelectMode();
  }

  Future<void> deleteVideo(String id) async {
    final db = ref.read(databaseProvider);
    final downloadService = ref.read(downloadServiceProvider);

    final video = state.videos.where((v) => v.id == id).firstOrNull;
    if (video != null) {
      await downloadService.deleteFile(video.localPath);
      if (video.thumbnailPath != null) {
        await downloadService.deleteFile(video.thumbnailPath!);
      }
    }

    await db.deleteVideo(id);
  }
}

/// 资源库控制器 Provider（现代 Notifier）
final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);
