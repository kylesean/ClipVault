import 'package:clip_vault/features/decode/douyin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeCookie', () {
    test('请求头格式原样返回', () {
      expect(normalizeCookie('ttwid=abc; msToken=xyz'), 'ttwid=abc; msToken=xyz');
      expect(normalizeCookie('  a=1  '), 'a=1');
      expect(normalizeCookie(''), isEmpty);
    });

    test('Netscape cookies.txt 自动转换', () {
      const netscape =
          '# Netscape HTTP Cookie File\n'
          '#HttpOnly_.douyin.com\tTRUE\t/\tTRUE\t1893456000\tsid_tt\tabc123\n'
          '.douyin.com\tTRUE\t/\tFALSE\t1893456000\tttwid\txyz789\n'
          '.douyin.com\tTRUE\t/\tFALSE\t1893456000\tmsToken\tm123\n';
      expect(
        normalizeCookie(netscape),
        'sid_tt=abc123; ttwid=xyz789; msToken=m123',
      );
    });

    test('非标准多行文本不丢数据', () {
      const weird = 'not-a-cookie\nstill-not';
      expect(normalizeCookie(weird), weird);
    });
  });

  group('buildTransportCookie（下载路径）', () {
    test('整份 cookies.txt 原文转为单行头', () {
      const raw =
          '# Netscape HTTP Cookie File\n'
          '# https://curl.haxx.se/rfc/cookie_spec.html\n'
          '.douyin.com\tTRUE\t/\tTRUE\t1893456000\tttwid\ttw_xyz\n'
          'www.douyin.com\tFALSE\t/\tFALSE\t1793627746\tts_v_web_id\tverify_abc\n';
      final header = buildTransportCookie(raw);
      expect(header, 'ttwid=tw_xyz; ts_v_web_id=verify_abc');
      expect(header.contains('\n'), isFalse);
      expect(header.contains('\t'), isFalse);
      expect(header.contains('#'), isFalse);
    });

    test('空输入返回空串（下载不带 Cookie 头）', () {
      expect(buildTransportCookie(null), isEmpty);
      expect(buildTransportCookie('   '), isEmpty);
    });
  });
  group('buildCookie（解析路径）', () {
    test('用户 Cookie 排在前面', () {
      final header = buildCookie(userCookie: 'ttwid=real');
      expect(header.startsWith('ttwid=real'), isTrue);
      expect(header, contains('msToken='));
      expect(header, contains('verifyFp='));
    });

    test('用户已有的键不再追加伪造值（去重）', () {
      final header = buildCookie(
        userCookie: 'msToken=REAL; verifyFp=RV; s_v_web_id=RS; ttwid=x',
      );
      // 每个键只出现一次，且保留用户的值
      expect('msToken='.allMatches(header).length, 1);
      expect('verifyFp='.allMatches(header).length, 1);
      expect('s_v_web_id='.allMatches(header).length, 1);
      expect(header, contains('msToken=REAL'));
      expect(header, isNot(contains('==')));
    });

    test('缺的键才补伪造值', () {
      final header = buildCookie(userCookie: 'ttwid=x');
      expect(header, contains('ttwid=x'));
      expect('msToken='.allMatches(header).length, 1);
      expect(header, contains('=='));
    });
  });
}
