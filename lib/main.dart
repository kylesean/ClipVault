import 'package:clip_vault/app.dart';
import 'package:clip_vault/core/theme/app_theme.dart';
import 'package:clip_vault/features/download/download_controller.dart';
import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/shared/services/notification_service.dart';
import 'package:clip_vault/shared/services/share_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 预加载持久化设置，避免启动时读取到默认值/竞态覆盖
  final initialSettings = await SettingsState.load();

  // 初始化本地通知
  final notificationService = NotificationService();
  await notificationService.init();

  runApp(
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(initialSettings),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const ClipVaultApp(),
    ),
  );
}

class ClipVaultApp extends ConsumerStatefulWidget {
  const ClipVaultApp({super.key});

  @override
  ConsumerState<ClipVaultApp> createState() => _ClipVaultAppState();
}

class _ClipVaultAppState extends ConsumerState<ClipVaultApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 初始化分享接收服务
    ref.read(shareIntentServiceProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.clipboardMonitor) return;

    final service = ref.read(shareIntentServiceProvider);
    final url = await service.checkClipboard();
    if (url != null && mounted) {
      _showClipboardDialog(url);
    }
  }

  void _showClipboardDialog(String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('检测到视频链接，是否下载？'),
        action: SnackBarAction(
          label: '下载',
          onPressed: () {
            ref.read(downloadControllerProvider.notifier).parseUrl(url);
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp.router(
      title: 'ClipVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: router,
    );
  }
}
