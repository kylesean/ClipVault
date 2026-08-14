import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知服务（下载完成提醒）
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 应用启动时初始化（Android 需在 MainActivity 之外调用）
  Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    _initialized = true;
  }

  /// 下载完成通知
  Future<void> showDownloadComplete(String title) async {
    if (!_initialized) return;
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _plugin.show(
      id,
      '下载完成',
      title,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'downloads',
          '下载通知',
          channelDescription: '视频下载完成提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// 通知服务 Provider
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
