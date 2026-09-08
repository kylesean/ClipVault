import 'package:clip_vault/features/library/library_controller.dart';
import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/main.dart';
import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/download_service.dart';
import 'package:clip_vault/shared/services/notification_service.dart';
import 'package:clip_vault/shared/services/providers.dart';
import 'package:clip_vault/shared/services/share_intent_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubDownloadService extends DownloadService {
  _StubDownloadService() : super();
}

/// 不触碰平台通道的分享服务桩
class _StubShareIntentService extends ShareIntentService {
  _StubShareIntentService(super.ref);

  @override
  void init() {}

  @override
  Future<String?> checkClipboard() async => null;
}

/// 不订阅数据库流的资源库控制器桩（避免 fake-async 环境残留定时器）
class _StubLibraryController extends LibraryController {
  @override
  LibraryState build() => const LibraryState(isLoading: false);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  List<Override> overrides() => [
        databaseProvider.overrideWithValue(db),
        downloadServiceProvider.overrideWithValue(_StubDownloadService()),
        initialSettingsProvider.overrideWithValue(const SettingsState()),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        shareIntentServiceProvider.overrideWith(
          (ref) => _StubShareIntentService(ref),
        ),
        libraryControllerProvider.overrideWith(() => _StubLibraryController()),
      ];

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const ClipVaultApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('AppShell 渲染底部导航栏', (tester) async {
    await pumpApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('资源库'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('底部导航可切换到资源库', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('资源库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('暂无视频'), findsOneWidget);
  });
}
