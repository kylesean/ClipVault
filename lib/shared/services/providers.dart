import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/download_service.dart';
import 'package:clip_vault/shared/services/parse_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 数据库 Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// 下载服务 Provider（监听 Cookie 变化）
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return DownloadService(cookie: settings.cookie);
});

/// 解析客户端 Provider（纯端，监听 Cookie，变化时自动重建）
final parseApiClientProvider = Provider<ParseApiClient>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return ParseApiClient(cookie: settings.cookie);
});
