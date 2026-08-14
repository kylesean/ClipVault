import 'package:clip_vault/core/utils/url_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlUtils.extractUrl', () {
    test('提取纯链接', () {
      expect(
        UrlUtils.extractUrl('https://v.douyin.com/abc'),
        'https://v.douyin.com/abc',
      );
    });

    test('裁剪尾部中文标点', () {
      expect(
        UrlUtils.extractUrl('https://v.douyin.com/abc，快去'),
        'https://v.douyin.com/abc',
      );
      expect(
        UrlUtils.extractUrl('https://v.douyin.com/abc。'),
        'https://v.douyin.com/abc',
      );
      expect(
        UrlUtils.extractUrl('https://youtu.be/abc？'),
        'https://youtu.be/abc',
      );
    });

    test('裁剪尾部英文标点/括号', () {
      expect(
        UrlUtils.extractUrl('(https://youtu.be/abc)'),
        'https://youtu.be/abc',
      );
      expect(
        UrlUtils.extractUrl('https://www.bilibili.com/video/BV1xx411c7mD，'),
        'https://www.bilibili.com/video/BV1xx411c7mD',
      );
    });

    test('无链接返回 null', () {
      expect(UrlUtils.extractUrl('这是一段普通文本'), isNull);
      expect(UrlUtils.extractUrl(''), isNull);
    });
  });

  group('UrlUtils.detectPlatform', () {
    test('识别主域', () {
      expect(
        UrlUtils.detectPlatform('https://www.douyin.com/video/123'),
        'douyin',
      );
      expect(
        UrlUtils.detectPlatform('https://www.bilibili.com/video/BV1xx'),
        'bilibili',
      );
      expect(
        UrlUtils.detectPlatform('https://youtu.be/dQw4w9WgXcQ'),
        'youtube',
      );
      expect(UrlUtils.detectPlatform('https://vm.tiktok.com/abc'), 'tiktok');
    });

    test('识别子域', () {
      expect(UrlUtils.detectPlatform('https://v.douyin.com/abc'), 'douyin');
      expect(UrlUtils.detectPlatform('https://b23.tv/abc'), 'bilibili');
      expect(UrlUtils.detectPlatform('https://xhslink.com/abc'), 'xiaohongshu');
    });

    test('host 锚定，拒绝伪造域名', () {
      expect(
        UrlUtils.detectPlatform('http://bilibili.com.evil.site/x'),
        isNull,
      );
      expect(
        UrlUtils.detectPlatform('http://douyin.com.evil.example/x'),
        isNull,
      );
      expect(UrlUtils.detectPlatform('http://evil-tiktok.com/x'), isNull);
    });

    test('非视频链接返回 null', () {
      expect(UrlUtils.detectPlatform('https://example.com/'), isNull);
      expect(UrlUtils.detectPlatform('随便写的文本'), isNull);
    });
  });

  group('UrlUtils.isValidVideoUrl', () {
    test('平台链接有效', () {
      expect(UrlUtils.isValidVideoUrl('https://v.douyin.com/abc'), isTrue);
      expect(
        UrlUtils.isValidVideoUrl('https://www.instagram.com/p/xyz/'),
        isTrue,
      );
    });

    test('无关链接无效', () {
      expect(UrlUtils.isValidVideoUrl('https://example.com/'), isFalse);
    });
  });

  group('UrlUtils.extractAllUrls', () {
    test('提取文本中的多个链接', () {
      final urls = UrlUtils.extractAllUrls(
        '看这个 https://v.douyin.com/a 和 https://youtu.be/b，',
      );
      expect(urls, ['https://v.douyin.com/a', 'https://youtu.be/b']);
    });
  });
}
