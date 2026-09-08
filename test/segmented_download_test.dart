import 'dart:io';
import 'dart:math';

import 'package:clip_vault/shared/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSegments', () {
    test('小文件只返回单段（走单连接）', () {
      expect(splitSegments(1024), hasLength(1));
      expect(splitSegments(8 * 1024 * 1024), hasLength(1));
    });

    test('刚好整除：无缝无重叠', () {
      // 32MB / 8MB = 4 段
      final segs = splitSegments(32 * 1024 * 1024);
      expect(segs, hasLength(4));
      expect(segs.first.start, 0);
      expect(segs.last.end, 32 * 1024 * 1024 - 1);
      for (var i = 1; i < segs.length; i++) {
        expect(segs[i].start, segs[i - 1].end + 1);
      }
    });

    test('有余数：余数归最后一段，总长守恒', () {
      final total = 20 * 1024 * 1024 + 123;
      final segs = splitSegments(total);
      expect(segs.length, greaterThanOrEqualTo(2));
      var covered = 0;
      for (var i = 0; i < segs.length; i++) {
        if (i > 0) expect(segs[i].start, segs[i - 1].end + 1);
        covered += segs[i].end - segs[i].start + 1;
      }
      expect(segs.first.start, 0);
      expect(segs.last.end, total - 1);
      expect(covered, total);
    });

    test('连接数封顶 8', () {
      final segs = splitSegments(1024 * 1024 * 1024);
      expect(segs.length, lessThanOrEqualTo(8));
      var covered = 0;
      for (final s in segs) {
        covered += s.end - s.start + 1;
      }
      expect(covered, 1024 * 1024 * 1024);
    });

    test('非法输入返回空', () {
      expect(splitSegments(0), isEmpty);
      expect(splitSegments(-5), isEmpty);
    });
  });

  group('mergeParts', () {
    test('按序合并且删除分片', () async {
      final dir = await Directory.systemTemp.createTemp('clipvault_merge');
      try {
        final rand = Random(42);
        final expected = <int>[];
        final parts = <String>[];
        for (var i = 0; i < 4; i++) {
          // 覆盖跨 1MB 搬运边界的大小
          final bytes = List<int>.generate(
            300 * 1024 + i * 777,
            (_) => rand.nextInt(256),
          );
          expected.addAll(bytes);
          final path = '${dir.path}/v.part$i';
          await File(path).writeAsBytes(bytes);
          parts.add(path);
        }
        final target = '${dir.path}/video.mp4';
        await DownloadService.mergeParts(parts, target);

        final merged = await File(target).readAsBytes();
        expect(merged, expected);
        for (final p in parts) {
          expect(await File(p).exists(), isFalse);
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
