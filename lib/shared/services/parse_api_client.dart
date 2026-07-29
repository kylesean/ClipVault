import 'package:clip_vault/core/errors/app_exceptions.dart';
import 'package:clip_vault/shared/models/parse_result.dart';
import 'package:dio/dio.dart';

/// 后端解析服务 API 客户端
class ParseApiClient {
  final Dio _dio;

  ParseApiClient({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  /// 解析视频链接
  Future<ParseResult> parseUrl(String url) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/parse',
        data: {'url': url},
      );

      final data = response.data as Map<String, dynamic>;
      final code = data['code'] as int? ?? -1;

      if (code != 0) {
        throw ParseException(
          data['message'] as String? ?? '解析失败',
          url: url,
        );
      }

      return ParseResult.fromJson(data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const NetworkException('解析超时，请重试');
      }
      if (e.type == DioExceptionType.connectionError) {
        throw const NetworkException('无法连接解析服务，请检查网络');
      }
      throw NetworkException(
        '网络错误: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 健康检查
  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
