import 'package:clip_vault/core/utils/format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatUtils.formatFileSize', () {
    test('字节', () {
      expect(FormatUtils.formatFileSize(500), '500 B');
    });
    test('KB', () {
      expect(FormatUtils.formatFileSize(1024), '1.0 KB');
    });
    test('MB', () {
      expect(FormatUtils.formatFileSize(5 * 1024 * 1024), '5.0 MB');
    });
    test('GB', () {
      expect(FormatUtils.formatFileSize(3 * 1024 * 1024 * 1024), '3.00 GB');
    });
  });

  group('FormatUtils.formatDuration', () {
    test('分钟', () {
      expect(FormatUtils.formatDuration(65), '01:05');
    });
    test('小时', () {
      expect(FormatUtils.formatDuration(3661), '01:01:01');
    });
    test('零', () {
      expect(FormatUtils.formatDuration(0), '00:00');
    });
  });

  group('FormatUtils.formatSpeed', () {
    test('带 /s 后缀', () {
      expect(FormatUtils.formatSpeed(2048), '2.0 KB/s');
    });
  });

  group('FormatUtils.formatDate', () {
    test('刚刚', () {
      expect(FormatUtils.formatDate(DateTime.now()), '刚刚');
    });
    test('分钟前', () {
      expect(
        FormatUtils.formatDate(
          DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        '5 分钟前',
      );
    });
    test('小时前', () {
      expect(
        FormatUtils.formatDate(
          DateTime.now().subtract(const Duration(hours: 3)),
        ),
        '3 小时前',
      );
    });
    test('超过 7 天显示日期', () {
      final d = DateTime.now().subtract(const Duration(days: 10));
      final expected =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      expect(FormatUtils.formatDate(d), expected);
    });
  });
}
