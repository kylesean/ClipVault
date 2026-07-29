import 'dart:async';

import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:clip_vault/features/download/download_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// 分享接收 + 剪贴板监听服务
class ShareIntentService {
  final Ref _ref;
  StreamSubscription<List<SharedMediaFile>>? _intentSubscription;
  String? _lastClipboardContent;

  ShareIntentService(this._ref);

  /// 初始化分享接收
  void init() {
    // 监听从其他 APP 分享过来的内容
    _intentSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedMedia);

    // 处理 APP 冷启动时的分享
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then(_handleSharedMedia);
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    for (final file in files) {
      final text = file.type == SharedMediaType.text ? file.path : null;
      if (text != null) {
        _processSharedText(text);
      }
    }
  }

  /// 处理分享的文本内容
  void _processSharedText(String text) {
    final url = UrlUtils.extractUrl(text);
    if (url != null && UrlUtils.isValidVideoUrl(url)) {
      _ref.read(downloadControllerProvider.notifier).parseUrl(url);
    }
  }

  /// 检测剪贴板（APP 回到前台时调用）
  Future<String?> checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;

      if (text == null || text.isEmpty) return null;
      if (text == _lastClipboardContent) return null;

      final url = UrlUtils.extractUrl(text);
      if (url != null && UrlUtils.isValidVideoUrl(url)) {
        _lastClipboardContent = text;
        return url;
      }
    } catch (_) {
      // 某些平台可能拒绝剪贴板访问
    }
    return null;
  }

  /// 标记链接已忽略
  void markIgnored(String content) {
    _lastClipboardContent = content;
  }

  void dispose() {
    _intentSubscription?.cancel();
  }
}

/// 分享服务 Provider
final shareIntentServiceProvider = Provider<ShareIntentService>((ref) {
  final service = ShareIntentService(ref);
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});
