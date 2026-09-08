import 'package:clip_vault/features/decode/abogus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ABogus', () {
    test('与 Python 原实现逐字节一致（固定随机/时间）', () {
      final bogus = ABogus();
      expect(
        bogus.getValue(
          'device_platform=webapp&aid=6383&aweme_id=7345492945006595379&msToken=',
          startTime: 1700000000000,
          endTime: 1700000000006,
          random1: 1234,
          random2: 5678,
          random3: 9012,
        ),
        'E7mhBdugDifihdWk56KLfY3q6IWVYmQI0SVkMD2fwBDOqL39HMY29exoIBGvXY8jwG/'
        '-IeEjy4hbT3ohrQ2y0Hwf9W0L/25ksDSkKl5Q5xSSs1X9eghgJ04qmkt5SMx2RvB-'
        'rOXmqhZHKRbp09oHmhK4b1dzFgf3qJLzef==',
      );
    });

    test('Map 入参与 Python urlencode(dict) 一致', () {
      final bogus = ABogus();
      expect(
        bogus.getValue(
          {'aid': '6383', 'aweme_id': '1'},
          startTime: 1700000000000,
          endTime: 1700000000006,
          random1: 1234,
          random2: 5678,
          random3: 9012,
        ),
        'E7mhBdugDifihdWk56KLfY3q6UuVYmQI0SVkMD2fuaDOqL39HMY29exoIBGvXY8jwG/'
        '-IeEjy4hbT3ohrQ2y0Hwf9W0L/25ksDSkKl5Q5xSSs1X9eghgJ04qmkt5SMx2RvB-'
        'rOXmqhZHKRbp09oHmhK4b1dzFgf3qJLz4E==',
      );
    });

    test('默认调用结构合法（168 字符，s4 字母表）', () {
      final value = ABogus().getValue({'aid': '6383', 'aweme_id': '1'});
      expect(value.length, 168);
      expect(
        RegExp(r'^[A-Za-z0-9/\-+=]+$').hasMatch(value),
        isTrue,
      );
    });
  });
}
