// A-Bogus 签名算法的纯 Dart 移植。
//
// 原始作者：JoeanAmier（TikTokDownloader，GPLv3）；
// 经 Evil0ctal（Douyin_TikTok_Download_API，Apache-2.0）修改；
// 本文件由上述 Python 实现（backend/app/douyin_core/abogus.py）逐行移植，
// 保留原始作者信息与许可要求。仅使用当前抖音 Web API 在用的
// `get_value` 路径（SM3 双重哈希 + RC4 + s4 变体 Base64），
// 未使用的 `compress/sum`（旧 MD5 系）路径未移植。
//
// 移植对照：
//   - `random()`/`randint(a,b)` 语义与 Python 一致（含端点）
//   - `int(x)` 截断、`& 0xFFFFFFFF` 均显式保留
//   - `urlencode(dict)` 由调用方提供已编码串，保证“签名串 == 实际发送串”

import 'dart:math';

import 'package:clip_vault/features/decode/sm3.dart';
import 'package:flutter/foundation.dart';

const _endString = 'cus';

// 与服务端 UA 绑定的固定指纹（对应 Chrome 90 UA，勿改）。
const List<int> _uaCode = [
  76, 98, 15, 131, 97, 245, 224, 133, 122, 199, 241, 166, 79, 34,
  90, 191, 128, 126, 122, 98, 66, 11, 14, 40, 49, 110, 110, 173,
  67, 96, 138, 252,
];

// 默认浏览器环境串（ABogus() 无参构造时使用，与 Python __browser 一致）。
const String _defaultBrowser =
    '1536|742|1536|864|0|0|0|0|1536|864|1536|864|1536|742|24|24|MacIntel';

const Map<String, String> _alphabets = {
  's0':
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=',
  's1':
      'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
  's2':
      'Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
  's3':
      'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe',
  's4':
      'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe',
};

final _random = Random();

/// Python `random() * 10000` 的等价实现。
List<int> _randomList({
  double? fixed,
  int b = 170,
  int c = 85,
  int d = 0,
  int e = 0,
  int f = 0,
  int g = 0,
}) {
  final r = fixed ?? _random.nextDouble() * 10000;
  final ri = r.toInt();
  final v1 = ri & 255;
  final v2 = ri >> 8;
  return [v1 & b | d, v1 & c | e, v2 & b | f, v2 & c | g];
}

List<int> _list1({double? fixed}) =>
    _randomList(fixed: fixed, d: 1, e: 2, f: 5, g: 45 & 170);

List<int> _list2({double? fixed}) => _randomList(fixed: fixed, d: 1);

List<int> _list3({double? fixed}) =>
    _randomList(fixed: fixed, d: 1, f: 5);

String _generateString1({
  double? r1,
  double? r2,
  double? r3,
}) {
  return String.fromCharCodes([
    ..._list1(fixed: r1),
    ..._list2(fixed: r2),
    ..._list3(fixed: r3),
  ]);
}

/// 单次 SM3 → 32 字节整数数组（对应 Python `sm3_to_array` 的单次调用）。
List<int> _sm3ToArrayBytes(List<int> data) => sm3(data);

List<int> _sm3ToArray(String data) => _sm3ToArrayBytes(data.codeUnits);

List<int> _generateMethodCode(String method) =>
    _sm3ToArrayBytes(_sm3ToArray('$method$_endString'));

List<int> _generateParamsCode(String params) =>
    _sm3ToArrayBytes(_sm3ToArray('$params$_endString'));

List<int> _list4(
  int a, int b, int c, int d, int e, int f, int g, int h, int i,
  int j, int k, int m, int n, int o, int p, int q, int r,
) {
  return [
    44, a, 0, 0, 0, 0, 24, b, n, 0, c, d, 0, 0, 0, 1, 0, 239,
    e, o, f, g, 0, 0, 0, 0, h, 0, 0, 14, i, j, 0, k, m, 3, p,
    1, q, 1, r, 0, 0, 0,
  ];
}

int _endCheckNum(List<int> a) {
  var r = 0;
  for (final i in a) {
    r ^= i;
  }
  return r;
}

String _rc4Encrypt(String plaintext, String key) {
  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key.codeUnitAt(i % key.length)) % 256;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }
  var i = 0;
  j = 0;
  final cipher = <int>[];
  for (var k = 0; k < plaintext.length; k++) {
    i = (i + 1) % 256;
    j = (j + s[i]) % 256;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
    final tt = (s[i] + s[j]) % 256;
    cipher.add(s[tt] ^ plaintext.codeUnitAt(k));
  }
  return String.fromCharCodes(cipher);
}

String _generateResult(String s, String alphabet) {
  final table = _alphabets[alphabet]!;
  const masks = [0xFC0000, 0x03F000, 0x0FC0, 0x3F];
  const shifts = [18, 12, 6, 0];
  final r = <String>[];
  for (var i = 0; i < s.length; i += 3) {
    int n;
    if (i + 2 < s.length) {
      n =
          (s.codeUnitAt(i) << 16) |
          (s.codeUnitAt(i + 1) << 8) |
          s.codeUnitAt(i + 2);
    } else if (i + 1 < s.length) {
      n = (s.codeUnitAt(i) << 16) | (s.codeUnitAt(i + 1) << 8);
    } else {
      n = s.codeUnitAt(i) << 16;
    }
    for (var k = 0; k < 4; k++) {
      if (shifts[k] == 6 && i + 1 >= s.length) break;
      if (shifts[k] == 0 && i + 2 >= s.length) break;
      r.add(table[(n & masks[k]) >> shifts[k]]);
    }
  }
  final padLen = (4 - r.length % 4) % 4;
  for (var k = 0; k < padLen; k++) {
    r.add('=');
  }
  return r.join();
}

/// 测试探针：暴露中间哈希，用于与 Python 原实现交叉验证（跟版时排查）。
@visibleForTesting
List<int> debugParamsCode(String params) => _generateParamsCode(params);

/// 测试探针：暴露中间哈希，用于与 Python 原实现交叉验证（跟版时排查）。
@visibleForTesting
List<int> debugMethodCode(String method) => _generateMethodCode(method);

/// A-Bogus 签名器（与 Python `ABogus` 同构）。
class ABogus {
  ABogus();

  String _generateString2(
    String urlParams, {
    String method = 'GET',
    int startTime = 0,
    int endTime = 0,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final st = startTime == 0 ? now : startTime;
    // Python: randint(4, 8) 含两端
    final et = endTime == 0 ? st + 4 + _random.nextInt(5) : endTime;
    final paramsArray = _generateParamsCode(urlParams);
    final methodArray = _generateMethodCode(method);
    const browser = _defaultBrowser;
    final browserCode = browser.codeUnits;
    final a = _list4(
      (et >> 24) & 255,
      paramsArray[21],
      _uaCode[23],
      (et >> 16) & 255,
      paramsArray[22],
      _uaCode[24],
      (et >> 8) & 255,
      et & 255,
      (st >> 24) & 255,
      (st >> 16) & 255,
      (st >> 8) & 255,
      st & 255,
      methodArray[21],
      methodArray[22],
      (et ~/ 4294967296),
      (st ~/ 4294967296),
      browser.length,
    );
    final check = _endCheckNum(a);
    a.addAll(browserCode);
    a.add(check);
    return _rc4Encrypt(String.fromCharCodes(a), 'y');
  }

  /// 生成 `a_bogus`（调用方自行 `Uri.encodeComponent`）。
  ///
  /// [urlParams] 既可以是已编码的 query 串，也可以是参数 Map
  /// （Map 按插入序编码；**签名串必须与实际发送的 query 完全一致**）。
  String getValue(
    Object urlParams, {
    String method = 'GET',
    int startTime = 0,
    int endTime = 0,
    double? random1,
    double? random2,
    double? random3,
  }) {
    final paramsString = urlParams is Map
        ? urlParams.entries
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent('${e.key}')}='
                    '${Uri.encodeQueryComponent('${e.value}')}',
              )
              .join('&')
        : urlParams as String;
    final string1 = _generateString1(r1: random1, r2: random2, r3: random3);
    final string2 = _generateString2(
      paramsString,
      method: method,
      startTime: startTime,
      endTime: endTime,
    );
    return _generateResult('$string1$string2', 's4');
  }
}
