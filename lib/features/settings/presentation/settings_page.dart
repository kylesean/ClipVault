import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clip_vault/core/constants/app_constants.dart';

const _keyClipboard = 'settings_clipboard_monitor';
const _keyMaxDownloads = 'settings_max_concurrent_downloads';
const _keyNotification = 'settings_download_notification';
const _keyThemeMode = 'settings_theme_mode';
const _keyServerUrl = 'settings_server_url';
const _keyApiToken = 'settings_api_token';

/// 设置状态
class SettingsState {
  final bool clipboardMonitor;
  final int maxConcurrentDownloads;
  final bool downloadNotification;
  final ThemeMode themeMode;
  final String serverUrl;
  final String apiToken;

  const SettingsState({
    this.clipboardMonitor = true,
    this.maxConcurrentDownloads = AppConstants.defaultMaxConcurrentDownloads,
    this.downloadNotification = true,
    this.themeMode = ThemeMode.system,
    this.serverUrl = AppConstants.parseApiBaseUrl,
    this.apiToken = '',
  });

  SettingsState copyWith({
    bool? clipboardMonitor,
    int? maxConcurrentDownloads,
    bool? downloadNotification,
    ThemeMode? themeMode,
    String? serverUrl,
    String? apiToken,
  }) {
    return SettingsState(
      clipboardMonitor: clipboardMonitor ?? this.clipboardMonitor,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadNotification: downloadNotification ?? this.downloadNotification,
      themeMode: themeMode ?? this.themeMode,
      serverUrl: serverUrl ?? this.serverUrl,
      apiToken: apiToken ?? this.apiToken,
    );
  }

  /// 同步加载持久化配置（在 runApp 之前调用，避免启动竞态）
  static Future<SettingsState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_keyThemeMode) ?? 0;
    final themeMode = (themeIndex >= 0 && themeIndex < ThemeMode.values.length)
        ? ThemeMode.values[themeIndex]
        : ThemeMode.system;
    return SettingsState(
      clipboardMonitor: prefs.getBool(_keyClipboard) ?? true,
      maxConcurrentDownloads:
          prefs.getInt(_keyMaxDownloads) ??
          AppConstants.defaultMaxConcurrentDownloads,
      downloadNotification: prefs.getBool(_keyNotification) ?? true,
      themeMode: themeMode,
      serverUrl: prefs.getString(_keyServerUrl) ?? AppConstants.parseApiBaseUrl,
      apiToken: prefs.getString(_keyApiToken) ?? '',
    );
  }
}

/// 启动时注入的初始设置（由 main() 预加载后 override）
final initialSettingsProvider = Provider<SettingsState?>((ref) => null);

/// 现代 Riverpod Notifier（替代已废弃的 StateNotifier）
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    // 初始值由 main() 预加载注入，保证首次读取即为最终值
    return ref.watch(initialSettingsProvider) ?? const SettingsState();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyClipboard, state.clipboardMonitor);
    await prefs.setInt(_keyMaxDownloads, state.maxConcurrentDownloads);
    await prefs.setBool(_keyNotification, state.downloadNotification);
    await prefs.setInt(_keyThemeMode, state.themeMode.index);
    await prefs.setString(_keyServerUrl, state.serverUrl);
    await prefs.setString(_keyApiToken, state.apiToken);
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

  void setServerUrl(String url) {
    state = state.copyWith(serverUrl: url.trim());
    _persist();
  }

  void setApiToken(String token) {
    state = state.copyWith(apiToken: token.trim());
    _persist();
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

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

          // 服务器
          _buildSectionHeader(context, '服务器'),
          _ServerUrlTile(
            currentUrl: settings.serverUrl,
            onSave: controller.setServerUrl,
          ),
          _ApiTokenTile(
            currentToken: settings.apiToken,
            onSave: controller.setApiToken,
          ),

          const Divider(),

          // 关于
          _buildSectionHeader(context, '关于'),
          const ListTile(title: Text('版本'), subtitle: Text('ClipVault v1.0.0')),
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

/// 服务器地址配置组件
class _ServerUrlTile extends StatefulWidget {
  final String currentUrl;
  final ValueChanged<String> onSave;

  const _ServerUrlTile({required this.currentUrl, required this.onSave});

  @override
  State<_ServerUrlTile> createState() => _ServerUrlTileState();
}

class _ServerUrlTileState extends State<_ServerUrlTile> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_ServerUrlTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在未编辑时同步外部变化，避免覆盖正在输入的内容
    if (oldWidget.currentUrl != widget.currentUrl && !_focusNode.hasFocus) {
      _controller.text = widget.currentUrl;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('服务器地址已保存'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: '解析服务地址',
              hintText: 'http://your-server:8000',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded),
                onPressed: _save,
              ),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Text(
            '部署后修改为你的服务器地址，如 https://api.example.com',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// API Token 配置组件（服务端设置 CLIPVAULT_API_TOKEN 后填写）
class _ApiTokenTile extends StatefulWidget {
  final String currentToken;
  final ValueChanged<String> onSave;

  const _ApiTokenTile({required this.currentToken, required this.onSave});

  @override
  State<_ApiTokenTile> createState() => _ApiTokenTileState();
}

class _ApiTokenTileState extends State<_ApiTokenTile> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentToken);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_ApiTokenTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentToken != widget.currentToken && !_focusNode.hasFocus) {
      _controller.text = widget.currentToken;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API Token 已保存'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            obscureText: _obscured,
            decoration: InputDecoration(
              labelText: 'API Token（可选）',
              hintText: '服务端 CLIPVAULT_API_TOKEN',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.check_rounded, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '服务端已设置 CLIPVAULT_API_TOKEN 时填写，留空则不发送',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
