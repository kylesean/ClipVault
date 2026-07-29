import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 解析 API 客户端 Provider
final parseApiClientProvider = Provider<ParseApiClient>((ref) {
  return ParseApiClient();
});
