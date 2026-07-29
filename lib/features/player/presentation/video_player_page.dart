import 'package:clip_vault/core/utils/format_utils.dart';
import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;
import 'package:saver_gallery/saver_gallery.dart';
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
  Video? _video;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = mk.VideoController(_player);
    _loadVideo();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    final db = ref.read(databaseProvider);
    final video = await db.getVideoById(widget.videoId);
    if (mounted) {
      setState(() {
        _video = video;
        _isLoading = false;
      });
      if (video != null) {
        _player.open(Media(video.localPath));
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_video == null) return;

    try {
      final result = await SaverGallery.saveFile(
        filePath: _video!.localPath,
        fileName: '${_video!.title}.mp4',
        androidRelativePath: 'Movies/ClipVault',
        skipIfExists: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isSuccess ? '已保存到相册' : '保存失败: ${result.errorMessage}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('链接已复制')),
                  );
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
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
