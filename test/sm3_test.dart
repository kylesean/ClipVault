import 'package:clip_vault/features/decode/sm3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SM3', () {
    test('向量 abc（与 gmssl/教科书实现交叉验证）', () {
      expect(
        sm3Hex('abc'),
        '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0',
      );
    });

    test('向量 abcd×16（64 字节，跨填充块）', () {
      expect(
        sm3Hex('abcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcd'),
        'debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732',
      );
    });

    test('向量 空串', () {
      expect(
        sm3Hex(''),
        '1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b',
      );
    });

    test('输出恒为 32 字节且确定', () {
      expect(sm3('hello douyin'.codeUnits), hasLength(32));
      expect(sm3Hex('a_bogus'), sm3Hex('a_bogus'));
    });
  });
}
