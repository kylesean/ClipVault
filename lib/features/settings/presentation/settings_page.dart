import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clip_vault/core/constants/app_constants.dart';

/// 设置状态
class SettingsState {
  final bool clipboardMonitor;
  final int maxConcurrentDownloads;
  final bool downloadNotification;
  final ThemeMode themeMode;

  const SettingsState({
    this.clipboardMonitor = true,
    this.maxConcurrentDownloads = AppConstants.defaultMaxConcurrentDownloads,
    this.downloadNotification = true,
    this.themeMode = ThemeMode.system,
  });

  SettingsState copyWith({
    bool? clipboardMonitor,
    int? maxConcurrentDownloads,
    bool? downloadNotification,
    ThemeMode? themeMode,
  }) {
    return SettingsState(
      clipboardMonitor: clipboardMonitor ?? this.clipboardMonitor,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadNotification: downloadNotification ?? this.downloadNotification,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

/// 现代 Riverpod Notifier（替代已废弃的 StateNotifier）
class SettingsController extends Notifier<SettingsState> {
  static const _keyClipboard = 'settings_clipboard_monitor';
  static const _keyMaxDownloads = 'settings_max_concurrent_downloads';
  static const _keyNotification = 'settings_download_notification';
  static const _keyThemeMode = 'settings_theme_mode';

  @override
  SettingsState build() {
    // 初始状态，异步加载持久化配置后更新
    _loadFromPrefs();
    return const SettingsState();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      clipboardMonitor: prefs.getBool(_keyClipboard) ?? true,
      maxConcurrentDownloads:
          prefs.getInt(_keyMaxDownloads) ??
          AppConstants.defaultMaxConcurrentDownloads,
      downloadNotification: prefs.getBool(_keyNotification) ?? true,
      themeMode: ThemeMode.values[prefs.getInt(_keyThemeMode) ?? 0],
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyClipboard, state.clipboardMonitor);
    await prefs.setInt(_keyMaxDownloads, state.maxConcurrentDownloads);
    await prefs.setBool(_keyNotification, state.downloadNotification);
    await prefs.setInt(_keyThemeMode, state.themeMode.index);
  }

  void setClipboardMonitor(bool value) {
    state = state.copyWith(clipboardMonitor: value);
    _persist();
  }

  void setMaxConcurrentDownloads(int value) {
    state = state.copyWith(maxConcurrentDownloads: value);
    _persist();
  }

  void setDownloadNotification(bool value) {
    state = state.copyWith(downloadNotification: value);
    _persist();
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _persist();
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

/// 设置页面
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 通用设置
          _buildSectionHeader(context, '通用'),
          SwitchListTile(
            title: const Text('剪贴板监听'),
            subtitle: const Text('回到前台时自动检测视频链接'),
            value: settings.clipboardMonitor,
            onChanged: controller.setClipboardMonitor,
          ),
          SwitchListTile(
            title: const Text('下载完成通知'),
            subtitle: const Text('视频下载完成后推送本地通知'),
            value: settings.downloadNotification,
            onChanged: controller.setDownloadNotification,
          ),

          const Divider(),

          // 下载设置
          _buildSectionHeader(context, '下载'),
          ListTile(
            title: const Text('最大并发下载数'),
            subtitle: Text('当前：${settings.maxConcurrentDownloads}'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {settings.maxConcurrentDownloads},
              onSelectionChanged: (v) =>
                  controller.setMaxConcurrentDownloads(v.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const Divider(),

          // 外观
          _buildSectionHeader(context, '外观'),
          ListTile(
            title: const Text('主题模式'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (v) => controller.setThemeMode(v.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const Divider(),

          // 关于
          _buildSectionHeader(context, '关于'),
          const ListTile(
            title: Text('版本'),
            subtitle: Text('ClipVault v1.0.0'),
          ),
          const ListTile(
            title: Text('解析引擎'),
            subtitle: Text('yt-dlp (1800+ 站点支持)'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
