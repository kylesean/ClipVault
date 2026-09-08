import 'dart:async';
import 'dart:io';

import 'package:clip_vault/core/utils/format_utils.dart';
import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;
import 'package:share_plus/share_plus.dart';

/// 视频详情/播放页面
class VideoPlayerPage extends ConsumerStatefulWidget {
  final String videoId;

  const VideoPlayerPage({super.key, required this.videoId});

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> {
  late final Player _player;
  late final mk.VideoController _videoController;
  StreamSubscription<dynamic>? _errorSub;
  Video? _video;
  bool _isLoading = true;
  String? _playbackError;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = mk.VideoController(_player);
    // 监听播放器错误（文件损坏/缺失等）
    _errorSub = _player.stream.error.listen((error) {
      if (!mounted) return;
      setState(() => _playbackError = '视频播放失败: $error');
    });
    _loadVideo();
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    final db = ref.read(databaseProvider);
    final video = await db.getVideoById(widget.videoId);
    if (!mounted) return;
    setState(() {
      _video = video;
      _isLoading = false;
    });
    if (video != null) {
      final file = File(video.localPath);
      if (!file.existsSync()) {
        setState(() => _playbackError = '视频文件不存在或已被删除');
        return;
      }
      unawaited(_player.open(Media(video.localPath)));
    }
  }

  Future<void> _saveToGallery() async {
    if (_video == null) return;

    try {
      // Android 10 以下需要运行时权限
      if (!await Gal.hasAccess(toAlbum: true)) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('未获得相册权限，无法保存')));
          }
          return;
        }
      }
      await Gal.putVideo(_video!.localPath, album: 'ClipVault');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存到相册')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  Future<void> _deleteVideo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除「${_video!.title}」？'),
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

    if (confirmed == true && _video != null) {
      final db = ref.read(databaseProvider);
      final downloadService = ref.read(downloadServiceProvider);

      await downloadService.deleteFile(_video!.localPath);
      if (_video!.thumbnailPath != null) {
        await downloadService.deleteFile(_video!.thumbnailPath!);
      }
      await db.deleteVideo(_video!.id);

      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_video == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('视频不存在')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _video!.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'save':
                  _saveToGallery();
                case 'share':
                  Share.share(_video!.originalUrl);
                case 'copy':
                  Clipboard.setData(ClipboardData(text: _video!.originalUrl));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('链接已复制')));
                case 'delete':
                  _deleteVideo();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.save_alt_rounded),
                  title: Text('保存到相册'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.share_rounded),
                  title: Text('分享链接'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_rounded),
                  title: Text('复制原始链接'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_rounded, color: Colors.red),
                  title: Text('删除视频', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 视频播放器
            AspectRatio(
              aspectRatio: 16 / 9,
              child: mk.Video(controller: _videoController),
            ),

            // 播放错误提示
            if (_playbackError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _playbackError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 视频信息
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _video!.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.person_rounded, _video!.author),
                  _buildInfoRow(
                    Icons.language_rounded,
                    UrlUtils.platformDisplayName(_video!.platform),
                  ),
                  _buildInfoRow(
                    Icons.timer_rounded,
                    FormatUtils.formatDuration(_video!.durationSeconds),
                  ),
                  _buildInfoRow(
                    Icons.storage_rounded,
                    FormatUtils.formatFileSize(_video!.fileSizeBytes),
                  ),
                  _buildInfoRow(
                    Icons.calendar_today_rounded,
                    FormatUtils.formatDate(_video!.downloadedAt),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
