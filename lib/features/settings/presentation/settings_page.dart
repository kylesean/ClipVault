import 'package:clip_vault/core/constants/app_constants.dart';
import 'package:clip_vault/features/decode/douyin_api.dart'
    show normalizeCookie;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyClipboard = 'settings_clipboard_monitor';
const _keyMaxDownloads = 'settings_max_concurrent_downloads';
const _keyNotification = 'settings_download_notification';
const _keyThemeMode = 'settings_theme_mode';
const _keyCookie = 'settings_cookie';

/// 设置状态（纯端：代理已删除，仅保留 Cookie）
class SettingsState {
  final bool clipboardMonitor;
  final int maxConcurrentDownloads;
  final bool downloadNotification;
  final ThemeMode themeMode;
  final String cookie;

  const SettingsState({
    this.clipboardMonitor = true,
    this.maxConcurrentDownloads = AppConstants.defaultMaxConcurrentDownloads,
    this.downloadNotification = true,
    this.themeMode = ThemeMode.system,
    this.cookie = '',
  });

  SettingsState copyWith({
    bool? clipboardMonitor,
    int? maxConcurrentDownloads,
    bool? downloadNotification,
    ThemeMode? themeMode,
    String? cookie,
  }) {
    return SettingsState(
      clipboardMonitor: clipboardMonitor ?? this.clipboardMonitor,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadNotification: downloadNotification ?? this.downloadNotification,
      themeMode: themeMode ?? this.themeMode,
      cookie: cookie ?? this.cookie,
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
      cookie: prefs.getString(_keyCookie) ?? '',
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
    await prefs.setString(_keyCookie, state.cookie);
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

  void setCookie(String cookie) {
    state = state.copyWith(cookie: cookie.trim());
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

          // 网络
          _buildSectionHeader(context, '网络'),
          _CookieTile(
            currentCookie: settings.cookie,
            onSave: controller.setCookie,
          ),

          const Divider(),

          // 关于
          _buildSectionHeader(context, '关于'),
          const ListTile(title: Text('版本'), subtitle: Text('ClipVault v2.0.2')),
          const ListTile(
            title: Text('解析引擎'),
            subtitle: Text('A-Bogus 本地签名（抖音 / TikTok，无需服务端）'),
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

/// Cookie 配置（抖音解析失败时，粘贴浏览器 Cookie 可大幅提升成功率）
class _CookieTile extends StatefulWidget {
  final String currentCookie;
  final ValueChanged<String> onSave;

  const _CookieTile({required this.currentCookie, required this.onSave});

  @override
  State<_CookieTile> createState() => _CookieTileState();
}

class _CookieTileState extends State<_CookieTile> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  // 默认明文多行：保证 cookies.txt 粘贴不丢换行。
  // 注意 Flutter 断言 obscureText 与多行互斥
  //（'Obscured fields cannot be multiline'），所以隐藏时强制切回单行。
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCookie);
    _focusNode = FocusNode();
  }

  static int _countItems(String text) {
    final normalized = normalizeCookie(text);
    if (normalized.isEmpty) return 0;
    return normalized.split(';').where((e) => e.trim().isNotEmpty).length;
  }

  @override
  void didUpdateWidget(_CookieTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentCookie != widget.currentCookie &&
        !_focusNode.hasFocus) {
      _controller.text = widget.currentCookie;
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
    final n = _countItems(_controller.text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(n > 0 ? 'Cookie 已保存（已识别 $n 项）' : 'Cookie 已清空'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // widget.currentCookie 来自已落库的 SettingsState（内存+磁盘一致后更新），
    // _controller.text 是编辑框草稿。两者不一致 = 改了没存，一目了然。
    // 注意保存时会 trim，比较时同样 trim，避免尾换行导致警告消不掉。
    final savedCount = _countItems(widget.currentCookie);
    final dirty = _controller.text.trim() != widget.currentCookie;
    final draftCount = _countItems(_controller.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            obscureText: _obscured,
            // cookies.txt 是多行文本，明文时允许多行粘贴；
            // 隐藏时必须单行（框架断言要求）
            minLines: 1,
            maxLines: _obscured ? 1 : 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: 'Cookie（可选）',
              hintText: 'a=1; b=2，或直接粘贴 cookies.txt 导出的全部文本',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_rounded),
                    tooltip: '保存',
                    onPressed: _save,
                  ),
                  IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    tooltip: '显示/隐藏',
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                dirty ? Icons.warning_amber_rounded : Icons.check_rounded,
                size: 14,
                color: dirty ? Colors.orange : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  dirty
                      ? '有未保存的更改（草稿 $draftCount 项），点 ✓ 保存后生效'
                      : savedCount > 0
                      ? '已保存 $savedCount 项 Cookie，解析时自动携带'
                      : '空。抖音解析失败时粘贴浏览器 Cookie，记得点 ✓ 保存',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: dirty
                        ? Colors.orange
                        : Theme.of(context).colorScheme.outline,
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
