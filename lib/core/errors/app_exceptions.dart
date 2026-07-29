/// 应用错误类型定义
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

/// 链接解析失败
class ParseException extends AppException {
  final String? url;
  const ParseException(super.message, {this.url});
}

/// 下载失败
class DownloadException extends AppException {
  final String? taskId;
  const DownloadException(super.message, {this.taskId});
}

/// 网络错误
class NetworkException extends AppException {
  final int? statusCode;
  const NetworkException(super.message, {this.statusCode});
}

/// 存储/权限错误
class StorageException extends AppException {
  const StorageException(super.message);
}

/// 视频文件不存在
class FileNotFoundException extends AppException {
  final String path;
  const FileNotFoundException(this.path) : super('文件不存在: $path');
}
