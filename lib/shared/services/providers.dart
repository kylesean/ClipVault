import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/shared/services/database.dart';
import 'package:clip_vault/shared/services/download_service.dart';
import 'package:clip_vault/shared/services/parse_api_client.dart';

/// 数据库 Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// 下载服务 Provider
final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService();
});

/// 解析 API 客户端 Provider（监听设置中的服务器地址，变化时自动重建）
final parseApiClientProvider = Provider<ParseApiClient>((ref) {
  final serverUrl = ref.watch(settingsControllerProvider).serverUrl;
  return ParseApiClient(baseUrl: serverUrl);
});
