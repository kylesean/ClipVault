// SM3 密码杂凑算法（GB/T 32905-2016）的纯 Dart 实现。
//
// 用途：A-Bogus 签名中的双重 SM3（`method + "cus"` / `params + "cus"`）。
// 不引入第三方 crypto 依赖（主流 Dart 哈希库不带 SM3），~120 行自包含。
const _mask32 = 0xFFFFFFFF;

int _rotl(int x, int n) {
  x &= _mask32;
  n &= 31;
  if (n == 0) return x;
  return ((x << n) | (x >>> (32 - n))) & _mask32;
}

int _p0(int x) => (x ^ _rotl(x, 9) ^ _rotl(x, 17)) & _mask32;

int _p1(int x) => (x ^ _rotl(x, 15) ^ _rotl(x, 23)) & _mask32;

int _ff(int j, int x, int y, int z) {
  if (j < 16) return (x ^ y ^ z) & _mask32;
  return ((x & y) | (x & z) | (y & z)) & _mask32;
}

int _gg(int j, int x, int y, int z) {
  if (j < 16) return (x ^ y ^ z) & _mask32;
  return ((x & y) | ((~x & _mask32) & z)) & _mask32;
}

const List<int> _iv = [
  0x7380166f,
  0x4914b2b9,
  0x172442d7,
  0xda8a0600,
  0xa96f30bc,
  0x163138aa,
  0xe38dee4d,
  0xb0fb0e4e,
];

/// 对字节数组计算 SM3，返回 32 字节摘要。
List<int> sm3(List<int> message) {
  // ---- 填充：0x80 + k 个 0x00 + 64 位大端比特长度 ----
  final padded = List<int>.of(message)..add(0x80);
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  final bitLen = message.length * 8;
  for (var i = 7; i >= 0; i--) {
    padded.add((bitLen >>> (i * 8)) & 0xff);
  }

  final v = List<int>.of(_iv);
  final w = List<int>.filled(68, 0);
  final w1 = List<int>.filled(64, 0);

  for (var block = 0; block < padded.length ~/ 64; block++) {
    final off = block * 64;
    for (var j = 0; j < 16; j++) {
      w[j] =
          ((padded[off + j * 4] << 24) |
              (padded[off + j * 4 + 1] << 16) |
              (padded[off + j * 4 + 2] << 8) |
              padded[off + j * 4 + 3]) &
          _mask32;
    }
    for (var j = 16; j < 68; j++) {
      w[j] =
          (_p1(w[j - 16] ^ w[j - 9] ^ _rotl(w[j - 3], 15)) ^
              _rotl(w[j - 13], 7) ^
              w[j - 6]) &
          _mask32;
    }
    for (var j = 0; j < 64; j++) {
      w1[j] = (w[j] ^ w[j + 4]) & _mask32;
    }

    var a = v[0];
    var b = v[1];
    var c = v[2];
    var d = v[3];
    var e = v[4];
    var f = v[5];
    var g = v[6];
    var h = v[7];

    for (var j = 0; j < 64; j++) {
      final t = j < 16 ? 0x79cc4519 : 0x7a879d8a;
      final ss1 = _rotl(
        (_rotl(a, 12) + e + _rotl(t, j)) & _mask32,
        7,
      );
      final ss2 = (ss1 ^ _rotl(a, 12)) & _mask32;
      final tt1 =
          (_ff(j, a, b, c) + d + ss2 + w1[j]) & _mask32;
      final tt2 =
          (_gg(j, e, f, g) + h + ss1 + w[j]) & _mask32;
      d = c;
      c = _rotl(b, 9);
      b = a;
      a = tt1;
      h = g;
      g = _rotl(f, 19);
      f = e;
      e = _p0(tt2);
    }

    v[0] ^= a;
    v[1] ^= b;
    v[2] ^= c;
    v[3] ^= d;
    v[4] ^= e;
    v[5] ^= f;
    v[6] ^= g;
    v[7] ^= h;
    for (var i = 0; i < 8; i++) {
      v[i] &= _mask32;
    }
  }

  final out = <int>[];
  for (final x in v) {
    out
      ..add((x >>> 24) & 0xff)
      ..add((x >>> 16) & 0xff)
      ..add((x >>> 8) & 0xff)
      ..add(x & 0xff);
  }
  return out;
}

/// 字符串的 SM3 十六进制摘要（小写）。
String sm3Hex(String input) {
  const hex = '0123456789abcdef';
  final bytes = sm3(input.codeUnits);
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(hex[(b >>> 4) & 0xf]);
    sb.write(hex[b & 0xf]);
  }
  return sb.toString();
}
