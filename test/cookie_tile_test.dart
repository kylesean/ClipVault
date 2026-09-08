import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 滚动到 Cookie 栏（它在 ListView 深处，懒加载，需先滚出来）。
Future<void> _showCookieTile(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(const SettingsState()),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byTooltip('保存'),
    500,
    // 页面里 TextField 自带 Scrollable，取第一个（ListView 的）
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  group('Cookie 栏', () {
    testWidgets('构建不触发 obscure+多行断言', (tester) async {
      await _showCookieTile(tester);
      expect(find.byTooltip('保存'), findsOneWidget);
    });

    testWidgets('显隐切换不断言', (tester) async {
      await _showCookieTile(tester);
      // 默认明文 → 点眼睛隐藏（单行）→ 再点显示（多行）
      await tester.tap(find.byTooltip('显示/隐藏'));
      await tester.pump();
      await tester.tap(find.byTooltip('显示/隐藏'));
      await tester.pump();
      expect(find.byTooltip('保存'), findsOneWidget);
    });

    testWidgets('粘贴→未保存提示→保存→已保存', (tester) async {
      await _showCookieTile(tester);
      // Cookie 框是页面上最后一个 TextField
      final cookieField = find.byType(TextField).last;

      await tester.enterText(cookieField, 'ttwid=abc');
      await tester.pump();
      expect(find.textContaining('有未保存的更改'), findsOneWidget);

      await tester.tap(find.byTooltip('保存'));
      await tester.pump();
      expect(find.textContaining('已保存 1 项'), findsOneWidget);
    });
  });
}
