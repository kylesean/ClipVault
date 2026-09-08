import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    initialSettingsProvider.overrideWithValue(const SettingsState()),
  ],
);

void main() {
  group('Settings 持久化', () {
    test('Cookie：setCookie 同步进内存并落盘，模拟重启可回读', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _container();
      addTearDown(container.dispose);

      container
          .read(settingsControllerProvider.notifier)
          .setCookie('ttwid=abc; msToken=xyz');

      // 解析用的内存状态必须同步更新
      expect(
        container.read(settingsControllerProvider).cookie,
        'ttwid=abc; msToken=xyz',
      );

      // 等待异步落盘后模拟重启回读
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final reloaded = await SettingsState.load();
      expect(reloaded.cookie, 'ttwid=abc; msToken=xyz');
    });

    test('Cookie：大段文本（含尾换行）存取不截断', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _container();
      addTearDown(container.dispose);

      final big = '${List.generate(50, (i) => 'k$i=v$i').join('; ')}\n';
      container.read(settingsControllerProvider.notifier).setCookie(big);
      expect(
        container.read(settingsControllerProvider).cookie,
        big.trim(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final reloaded = await SettingsState.load();
      expect(reloaded.cookie, big.trim());
    });
  });
}
