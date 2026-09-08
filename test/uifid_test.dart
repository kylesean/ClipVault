import 'package:clip_vault/features/decode/douyin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UIFID 收割', () {
    test('大小写不敏感提取 UIFID/ttwid，忽略无关项', () {
      final harvested = debugHarvestFingerprints([
        'UIFID=ui_abc123; Path=/; Domain=.douyin.com; Expires=Thu, 01-Jan-2030 00:00:00 GMT',
        'ttwid=tw_xyz; Path=/; HttpOnly',
        'odin_tt=zzz; Path=/',
        'empty=; Path=/',
        'garbage-without-equals',
      ]);
      expect(harvested['UIFID'], 'ui_abc123');
      expect(harvested['ttwid'], 'tw_xyz');
      expect(harvested.containsKey('odin_tt'), isFalse);
      expect(harvested.containsKey('empty'), isFalse);
    });

    test('小写 uifid 也能识别', () {
      final harvested = debugHarvestFingerprints([
        'uifid=lower_case_value; Path=/',
      ]);
      expect(harvested['uifid'], 'lower_case_value');
    });

    test('无 Set-Cookie 返回空表', () {
      expect(debugHarvestFingerprints(null), isEmpty);
      expect(debugHarvestFingerprints([]), isEmpty);
    });
  });

  group('收割并入', () {
    test('用户已有的键不覆盖，缺的补上', () {
      final merged = debugMergeHarvested('ttwid=user_tw; msToken=REAL', {
        'UIFID': 'ui_new',
        'ttwid': 'harvested_tw',
      });
      expect(merged, contains('ttwid=user_tw'));
      expect(merged, isNot(contains('harvested_tw')));
      expect(merged, contains('UIFID=ui_new'));
    });

    test('Netscape 原文先归一化再合并', () {
      const netscape =
          '.douyin.com\tTRUE\t/\tFALSE\t1893456000\tttwid\tns_tw\n'
          '.douyin.com\tTRUE\t/\tFALSE\t1893456000\tmsToken\tns_ms\n';
      final merged = debugMergeHarvested(netscape, {'UIFID': 'ui_new'});
      expect(merged, contains('ttwid=ns_tw'));
      expect(merged, contains('msToken=ns_ms'));
      expect(merged, contains('UIFID=ui_new'));
      expect(merged.contains('\t'), isFalse);
      expect(merged.contains('\n'), isFalse);
    });
  });

  group('签名参数表', () {
    test('uifid 参与签名（有值与空串占位）', () {
      final withValue = debugDetailParams('123', uifid: 'ui_abc');
      expect(withValue['uifid'], 'ui_abc');
      expect(withValue['aweme_id'], '123');
      // msToken 仍按上游置空
      expect(withValue['msToken'], isEmpty);

      final empty = debugDetailParams('123');
      expect(empty.containsKey('uifid'), isTrue);
      expect(empty['uifid'], isEmpty);
    });
  });

  group('buildCookie 传输消毒', () {
    test('换行制表符被压掉，不抛传输异常', () {
      final header = buildCookie(userCookie: 'a=1\nb=2\tx');
      expect(header.contains('\n'), isFalse);
      expect(header.contains('\t'), isFalse);
      expect(header.contains('\r'), isFalse);
    });
  });
}
