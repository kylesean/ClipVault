// 纯端解析客户端：替代原来的后端 `/api/parse` 调用。
//
// 接口与旧版保持一致（`parseUrl`），`DownloadController` 无需改动。
// 仅支持抖音 / TikTok；其他平台链接直接抛 [ParseException] 明示。
import 'package:clip_vault/core/errors/app_exceptions.dart';
import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:clip_vault/features/decode/douyin_api.dart';
import 'package:clip_vault/shared/models/parse_result.dart';
import 'package:dio/dio.dart';

/// 本地解析客户端（无服务端）。
class ParseApiClient {
  final Dio? _dio;
  final String? _cookie;

  /// [dio] 注入用于测试；[cookie] 用户粘贴的 Cookie，
  /// 显著提升抖音成功率。
  // 私有命名形参无法跨库传递（providers/测试需传参），保留初始化列表
  const ParseApiClient({Dio? dio, String? cookie})
    : _dio = dio, // ignore: prefer_initializing_formals
      _cookie = cookie; // ignore: prefer_initializing_formals

  /// 解析视频链接（抖音 / TikTok）。
  Future<ParseResult> parseUrl(String url) async {
    final link = UrlUtils.extractUrl(url)?.trim() ?? '';
    if (link.isEmpty) {
      throw const ParseException('链接不能为空');
    }
    final platform = UrlUtils.detectPlatform(link);
    if (platform == null) {
      throw ParseException('暂仅支持抖音 / TikTok 链接', url: url);
    }
    try {
      switch (platform) {
        case 'douyin':
          return await fetchDouyin(link, dio: _dio, cookie: _cookie);
        case 'tiktok':
          return await fetchTikTok(link, dio: _dio, cookie: _cookie);
        default:
          throw ParseException('暂仅支持抖音 / TikTok 链接', url: url);
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw ParseException('解析失败，请稍后重试（$e）', url: url);
    }
  }

  /// 兼容旧接口：纯端模式永远可用。
  Future<bool> healthCheck() async => true;
}
