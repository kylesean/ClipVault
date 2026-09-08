// 抖音 / TikTok 纯端解析客户端：直调官方 Web 接口，无需自建服务端。
//
// 抖音：短链跟随 → aweme_id → `aweme/v1/web/aweme/detail/`（A-Bogus 签名）。
// TikTok：短链跟随 → video_id → 作品页 `__UNIVERSAL_DATA_FOR_REHYDRATION__`
//   内嵌 JSON（免签名，低频自用稳定）。
// Cookie 策略：用户粘贴的 Cookie（设置页）+ 本地伪造 msToken/verifyFp；
//   解析失败 99% 是缺 Cookie 或 IP 被风控，错误信息会明示。

import 'dart:convert';
import 'dart:math';

import 'package:clip_vault/core/errors/app_exceptions.dart';
import 'package:clip_vault/features/decode/abogus.dart';
import 'package:clip_vault/shared/models/parse_result.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

/// 与 A-Bogus `ua_code` 对应的 UA（config.yaml 锁死版本，勿改）。
const String kDouyinUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36';

const String kDouyinReferer = 'https://www.douyin.com/';
const String kDouyinDetailEndpoint =
    'https://www.douyin.com/aweme/v1/web/aweme/detail/';

const String kTikTokUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const String kTikTokReferer = 'https://www.tiktok.com/';

/// 抖音详情接口固定参数（顺序参与签名，缺一不可）。
Map<String, String> _douyinDetailParams(String awemeId, {String uifid = ''}) => {
  'device_platform': 'webapp',
  'aid': '6383',
  'channel': 'channel_pc_web',
  'pc_client_type': '1',
  'version_code': '290100',
  'version_name': '29.1.0',
  'cookie_enabled': 'true',
  'screen_width': '1920',
  'screen_height': '1080',
  'browser_language': 'zh-CN',
  'browser_platform': 'Win32',
  'browser_name': 'Chrome',
  'browser_version': '130.0.0.0',
  'browser_online': 'true',
  'engine_name': 'Blink',
  'engine_version': '130.0.0.0',
  'os_name': 'Windows',
  'os_version': '10',
  'cpu_core_num': '12',
  'device_memory': '8',
  'platform': 'PC',
  'downlink': '10',
  'effective_type': '4g',
  'from_user_page': '1',
  'locate_query': 'false',
  'need_time_list': '1',
  'pc_libra_divert': 'Windows',
  'publish_video_strategy_type': '2',
  'round_trip_time': '0',
  'show_live_replay_strategy': '1',
  'time_list_query': '0',
    'whale_cut_token': '',
    'update_version_code': '170400',
    'aweme_id': awemeId,
    // WAF 点名要的设备指纹：必须参与签名（空串也要占位，见 douyin-cli）。
    // 真值从服务端 Set-Cookie（UIFID）收割，见 fetchDouyin。
    'uifid': uifid,
    // 与上游一致：msToken 在签名前置空
    'msToken': '',
};

// ---------------------------------------------------------------------------
// Token / 指纹（token_manager.py 的 Dart 移植）
// ---------------------------------------------------------------------------

const String _alnum =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
final _rand = Random();

String _randomStr(int length) => String.fromCharCodes(
  List<int>.generate(
    length,
    (_) => _alnum.codeUnitAt(_rand.nextInt(_alnum.length)),
  ),
);

/// 本地伪造 msToken（mssdk 接口的 strData 为 4KB 静态 blob，不再内嵌；
/// 上游 Python 实现同样在 mssdk 失败时回落到该值，实测可用）。
String genFalseMsToken() => '${_randomStr(126)}==';

/// verify_fp / s_v_web_id（纯本地算法）。
String genVerifyFp() {
  const base =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  var ms = DateTime.now().millisecondsSinceEpoch;
  var base36 = '';
  while (ms > 0) {
    final r = ms % 36;
    base36 = (r < 10 ? '$r' : String.fromCharCode(97 + r - 10)) + base36;
    ms ~/= 36;
  }
  final o = List<String>.filled(36, '');
  o[8] = '_';
  o[13] = '_';
  o[18] = '_';
  o[23] = '_';
  o[14] = '4';
  for (var i = 0; i < 36; i++) {
    if (o[i].isEmpty) {
      var n = _rand.nextInt(base.length);
      if (i == 19) n = 3 & n | 8;
      o[i] = base[n];
    }
  }
  return 'verify_${base36}_${o.join()}';
}

/// 归一化用户粘贴的 Cookie，兼容两种格式：
/// 1. 请求头格式：`a=1; b=2`（直接使用）；
/// 2. Netscape cookies.txt（如 "Get cookies.txt LOCALLY" 插件导出，自动转换）。
String normalizeCookie(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  if (!text.contains('\t') && !text.contains('\n')) return text;
  final parts = <String>[];
  for (final line in text.split('\n')) {
    final l = line.trim();
    if (l.isEmpty || (l.startsWith('#') && !l.startsWith('#HttpOnly_'))) {
      continue;
    }
    final fields = l.split('\t');
    if (fields.length >= 7) {
      final name = fields[5].trim();
      final value = fields[6].trim();
      if (name.isNotEmpty) parts.add('$name=$value');
    }
  }
  // 不是标准 Netscape 格式就原样返回，不丢数据
  if (parts.isEmpty) return text;
  return parts.join('; ');
}

/// 直连场景（CDN 下载）的 Cookie 头：只做归一化+消毒，不追加伪造标识。
/// 解析路径用 buildCookie（含伪造补齐），下载路径必须用这个——
/// 之前下载直接塞原文，多行 cookies.txt 会把 HTTP 头撑爆
///（FormatException: Invalid HTTP header field value）。
String buildTransportCookie(String? userCookie) {
  final normalized = normalizeCookie(userCookie ?? '');
  if (normalized.isEmpty) return '';
  return normalized.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
}

/// 组装请求 Cookie：用户 Cookie 优先，缺的键才用本地伪造值补齐。
///
/// 之前无条件追加伪造值会导致同一键出现两次
///（如 `msToken=真…; msToken=伪…`），部分 WAF 取最后一个值或直接判篡改，
/// 反而把有效的登录态冲掉 —— 有 Cookie 仍 403 的头号嫌疑。
String buildCookie({String? userCookie}) {
  final user = normalizeCookie(userCookie ?? '');
  final userKeys = <String>{};
  if (user.isNotEmpty) {
    for (final part in user.split(';')) {
      final eq = part.indexOf('=');
      final name = (eq < 0 ? part : part.substring(0, eq)).trim();
      if (name.isNotEmpty) userKeys.add(name);
    }
  }
  final parts = <String>[];
  if (user.isNotEmpty) parts.add(user);
  // 与上游一致：verifyFp / s_v_web_id 各自独立生成
  if (!userKeys.contains('msToken')) parts.add('msToken=${genFalseMsToken()}');
  if (!userKeys.contains('verifyFp')) parts.add('verifyFp=${genVerifyFp()}');
  if (!userKeys.contains('s_v_web_id')) {
    parts.add('s_v_web_id=${genVerifyFp()}');
  }
  // 传输消毒：换行/制表符进 Header 会直接抛传输异常，先压掉
  return parts.join('; ').replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
}

Dio _newParseDio({String? userAgent}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
      // 短链跟随（v.douyin.com）无浏览器 UA 会直接 403，
      // 所以默认头就按浏览器装，详情接口再按需覆盖。
      headers: {
        'User-Agent': userAgent ?? kDouyinUserAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    ),
  );
  return dio;
}

// ---------------------------------------------------------------------------
// 通用：短链跟随 + ID 提取
// ---------------------------------------------------------------------------

final _douyinIdPatterns = [
  RegExp(r'video/([^/?]*)'),
  RegExp(r'[?&]vid=(\d+)'),
  RegExp(r'note/([^/?]*)'),
  RegExp(r'modal_id=([0-9]+)'),
];
final _tikTokIdPattern = RegExp(r'/video/(\d+)');

Future<({String url, List<String> setCookies})> _resolveUrlWithCookies(
  Dio dio,
  String url,
  String platform,
  String referer,
) async {
  try {
    final resp = await dio.getUri<dynamic>(
      Uri.parse(url),
      options: Options(headers: {'Referer': referer}),
    );
    return (
      url: resp.realUri.toString(),
      setCookies: resp.headers['set-cookie'] ?? const [],
    );
  } on DioException catch (e) {
    throw _resolveError(e, platform);
  }
}

/// 从 Set-Cookie 收割 WAF 指纹（UIFID / ttwid 由服务端下发，真浏览器自带）。
/// 只收这两个，避免把会话无关的杂项也带上。
Map<String, String> _harvestFingerprints(List<String>? setCookies) {
  final out = <String, String>{};
  if (setCookies == null) return out;
  for (final h in setCookies) {
    final first = h.split(';').first.trim();
    final eq = first.indexOf('=');
    if (eq <= 0) continue;
    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (value.isEmpty) continue;
    final lower = name.toLowerCase();
    if (lower != 'uifid' && lower != 'ttwid') continue;
    if (out.keys.any((k) => k.toLowerCase() == lower)) continue;
    out[name] = value;
  }
  return out;
}

String? _uifidOf(Map<String, String> harvested) {
  for (final e in harvested.entries) {
    if (e.key.toLowerCase() == 'uifid') return e.value;
  }
  return null;
}

/// 用户 Cookie 里没有的收割项才追加（不覆盖登录态）。
String _mergeHarvested(String? userCookie, Map<String, String> harvested) {
  final normalized = normalizeCookie(userCookie ?? '');
  final existing = <String>{};
  if (normalized.isNotEmpty) {
    for (final part in normalized.split(';')) {
      final eq = part.indexOf('=');
      final name = (eq < 0 ? part : part.substring(0, eq)).trim().toLowerCase();
      if (name.isNotEmpty) existing.add(name);
    }
  }
  final parts = <String>[if (normalized.isNotEmpty) normalized];
  harvested.forEach((name, value) {
    if (!existing.contains(name.toLowerCase())) parts.add('$name=$value');
  });
  return parts.join('; ');
}

/// 兜底：直访首页拿 UIFID（浏览器首次访问即被 Set-Cookie）。
/// 失败返回 null（调用方用空串占位不断整个流程）。
Future<String?> _fetchHomepageUifid(Dio dio, String? cookie) async {
  try {
    final user = (cookie ?? '').trim();
    final resp = await dio.getUri<dynamic>(
      Uri.parse('https://www.douyin.com/'),
      options: Options(
        headers: {
          'Referer': 'https://www.douyin.com/',
          if (user.isNotEmpty) 'Cookie': user,
        },
      ),
    );
    return _uifidOf(_harvestFingerprints(resp.headers['set-cookie']));
  } catch (_) {
    return null;
  }
}

/// 短链跟随阶段的错误（带阶段标记，方便定位是短链挂还是详情接口挂）。
Never _resolveError(DioException e, String platform) {
  final status = e.response?.statusCode;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      throw NetworkException('$platform 短链解析超时，请重试');
    case DioExceptionType.connectionError:
      throw NetworkException('无法连接$platform，请检查网络或代理设置');
    default:
      throw NetworkException(
        '$platform 短链解析失败${status != null ? '（$status）' : ''}：'
        '请确认链接有效，或稍后重试',
        statusCode: status,
      );
  }
}

String _extractDouyinId(String finalUrl) {
  for (final p in _douyinIdPatterns) {
    final m = p.firstMatch(finalUrl);
    if (m != null && (m.group(1) ?? '').isNotEmpty) return m.group(1)!;
  }
  throw const ParseException('未在链接中找到作品 ID，请确认是抖音作品/视频页链接');
}

// ---------------------------------------------------------------------------
// JSON 安全读取 helpers（strict lints 下避免 dynamic 调用）
// ---------------------------------------------------------------------------

Map<String, dynamic>? _mapOf(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v is Map<String, dynamic> ? v : null;
}

String? _strOf(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v is String && v.isNotEmpty ? v : null;
}

List<dynamic>? _listOf(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v is List<dynamic> ? v : null;
}

int _intOf(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String? _firstUrlList(Map<String, dynamic>? addr) {
  if (addr == null) return null;
  final list = _listOf(addr, 'url_list');
  if (list == null || list.isEmpty) return null;
  final first = list.first;
  return first is String && first.isNotEmpty ? first : null;
}

/// 测试探针：Set-Cookie 收割（跟版/排障用）。
@visibleForTesting
Map<String, String> debugHarvestFingerprints(List<String>? setCookies) =>
    _harvestFingerprints(setCookies);

/// 测试探针：收割指纹并入用户 Cookie（跟版/排障用）。
@visibleForTesting
String debugMergeHarvested(String? userCookie, Map<String, String> harvested) =>
    _mergeHarvested(userCookie, harvested);

/// 测试探针：详情接口签名参数表（跟版/排障用）。
@visibleForTesting
Map<String, String> debugDetailParams(String awemeId, {String uifid = ''}) =>
    _douyinDetailParams(awemeId, uifid: uifid);

// ---------------------------------------------------------------------------
// 抖音：签名详情接口
// ---------------------------------------------------------------------------

final _qualityNum = RegExp(r'(\d{3,4})');
const _qualityFallback = {
  '1': '1080p',
  '10': '720p',
  '211': '720p',
  '112': '540p',
  '5': '540p',
  '104': '480p',
  '4': '360p',
};

String _qualityLabel(String? gearName, Object? qualityType) {
  if (gearName != null && gearName.isNotEmpty) {
    final m = _qualityNum.firstMatch(gearName);
    if (m != null) return '${m.group(1)}p';
  }
  if (qualityType != null) {
    return _qualityFallback['$qualityType'] ?? 'quality_$qualityType';
  }
  return 'unknown';
}

/// 解析单个分享链接为抖音作品（完整流程）。
Future<ParseResult> fetchDouyin(
  String url, {
  Dio? dio,
  String? cookie,
}) async {
  final client = dio ?? _newParseDio();
  // 短链跟随 + 顺手收割 Set-Cookie（UIFID/ttwid 由服务端下发）
  final resolved = await _resolveUrlWithCookies(
    client,
    url,
    '抖音',
    kDouyinReferer,
  );
  final awemeId = _extractDouyinId(resolved.url);
  final harvested = _harvestFingerprints(resolved.setCookies);
  var uifid = _uifidOf(harvested);
  // 短链链路上没拿到就直访首页补一次
  uifid ??= await _fetchHomepageUifid(client, cookie);
  // 收割到的指纹并入 Cookie（用户已有的不覆盖）
  final effectiveCookie = _mergeHarvested(cookie, harvested);

  final params = _douyinDetailParams(awemeId, uifid: uifid ?? '');
  final query = params.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
  // 签名串必须与实际发送的 query 完全一致
  final aBogus = ABogus().getValue(query);
  final endpoint =
      '$kDouyinDetailEndpoint?$query&a_bogus=${Uri.encodeComponent(aBogus)}';

  Map<String, dynamic> json;
  try {
    final resp = await client.getUri<Map<String, dynamic>>(
      Uri.parse(endpoint),
      options: Options(
        headers: {
          'User-Agent': kDouyinUserAgent,
          'Referer': kDouyinReferer,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          // 真实浏览器 XHR 自带，补齐降低 WAF 特征分
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
          // 真浏览器同时在 header 里带 uifid（有才带）
          if (uifid != null && uifid.isNotEmpty) 'uifid': uifid,
          'Cookie': buildCookie(userCookie: effectiveCookie),
        },
      ),
    );
    json = resp.data ?? {};
  } on DioException catch (e) {
    throw _detailError(e);
  }

  final videoData = _mapOf(json, 'aweme_detail');
  if (videoData == null) {
    throw const ParseException(
      '抖音接口未返回作品数据（可能需要粘贴 Cookie，或换网络重试）',
    );
  }
  return _douyinParseData(videoData);
}

ParseResult _douyinParseData(Map<String, dynamic> videoData) {
  final title = _strOf(videoData, 'desc') ?? '未知标题';
  final authorMap = _mapOf(videoData, 'author');
  final author =
      (authorMap == null
          ? null
          : (_strOf(authorMap, 'nickname') ??
                _strOf(authorMap, 'unique_id'))) ??
      '未知作者';

  final videoInfo = _mapOf(videoData, 'video') ?? {};
  var duration = _intOf(videoInfo, 'duration');
  if (duration == 0) duration = _intOf(videoData, 'duration');
  // 毫秒 → 秒
  if (duration > 1000) duration ~/= 1000;

  String? thumbnail;
  for (final key in ['origin_cover', 'cover', 'dynamic_cover']) {
    final cover = videoInfo[key];
    if (cover is Map<String, dynamic>) {
      thumbnail = _firstUrlList(cover);
      if (thumbnail != null) break;
    } else if (cover is String && cover.isNotEmpty) {
      thumbnail = cover;
      break;
    }
  }
  thumbnail ??= _firstUrlList(_mapOf(videoData, 'cover_data') != null
      ? _mapOf(_mapOf(videoData, 'cover_data')!, 'origin')
      : null);
  final coverRaw = videoData['cover'];
  if (thumbnail == null) {
    if (coverRaw is Map<String, dynamic>) {
      thumbnail = _firstUrlList(coverRaw);
    } else if (coverRaw is String && coverRaw.isNotEmpty) {
      thumbnail = coverRaw;
    }
  }

  final formats = _douyinFormats(videoData, videoInfo);
  if (formats.isEmpty) {
    throw const ParseException('未获取到可用的视频下载链接');
  }
  return ParseResult(
    title: title,
    author: author,
    platform: _strOf(videoData, 'platform') ?? 'douyin',
    duration: duration,
    thumbnail: thumbnail,
    formats: formats,
  );
}

List<VideoFormat> _douyinFormats(
  Map<String, dynamic> videoData,
  Map<String, dynamic> videoInfo,
) {
  final formats = <VideoFormat>[];
  void add(String quality, Object? url) {
    if (url is String &&
        url.isNotEmpty &&
        !formats.any((f) => f.url == url)) {
      formats.add(VideoFormat(quality: quality, url: url, ext: 'mp4'));
    }
  }

  final bitRates = _listOf(videoInfo, 'bit_rate');
  if (bitRates != null) {
    for (final br in bitRates) {
      if (br is! Map<String, dynamic>) continue;
      final playAddr = _mapOf(br, 'play_addr');
      final urls = playAddr == null ? null : _listOf(playAddr, 'url_list');
      if (urls != null && urls.isNotEmpty) {
        final q = _qualityLabel(
          br['gear_name'] is String ? br['gear_name'] as String : null,
          br['quality_type'],
        );
        add('无水印·$q', urls.first);
      }
    }
  }
  add('无水印', _firstUrlList(_mapOf(videoInfo, 'play_addr')));
  add('无水印·下载', _firstUrlList(_mapOf(videoInfo, 'download_addr')));
  add(
    '有水印',
    _firstUrlList(_mapOf(videoInfo, 'download_suffix_logo_addr')),
  );

  final vd = _mapOf(videoData, 'video_data');
  if (vd != null) {
    add('无水印·高清', vd['nwm_video_url_HQ']);
    add('无水印', vd['nwm_video_url']);
    add('有水印·高清', vd['wm_video_url_HQ']);
  }
  return formats;
}

// ---------------------------------------------------------------------------
// TikTok：作品页内嵌 JSON（免签名）
// ---------------------------------------------------------------------------

final _rehydrationRe = RegExp(
  r'<script[^>]*id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>',
  dotAll: true,
);

/// 解析单个分享链接为 TikTok 作品（完整流程）。
Future<ParseResult> fetchTikTok(
  String url, {
  Dio? dio,
  String? cookie,
}) async {
  final client = dio ?? _newParseDio(userAgent: kTikTokUserAgent);
  final finalUrl =
      (await _resolveUrlWithCookies(client, url, 'TikTok', kTikTokReferer))
          .url;
  final idMatch = _tikTokIdPattern.firstMatch(finalUrl);
  if (idMatch == null) {
    throw const ParseException('未在链接中找到 TikTok 视频 ID');
  }

  String html;
  try {
    final resp = await client.getUri<String>(
      Uri.parse(finalUrl),
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': kTikTokUserAgent,
          'Referer': kTikTokReferer,
          'Accept-Language': 'en-US,en;q=0.9',
          if ((cookie ?? '').trim().isNotEmpty) 'Cookie': cookie!.trim(),
        },
      ),
    );
    html = resp.data ?? '';
  } on DioException catch (e) {
    throw _networkError(e, 'TikTok');
  }

  final m = _rehydrationRe.firstMatch(html);
  if (m == null) {
    throw const ParseException(
      'TikTok 页面解析失败（可能被风控或需要代理/ Cookie）',
    );
  }
  Map<String, dynamic> root;
  try {
    root = jsonDecode(m.group(1)!) as Map<String, dynamic>;
  } catch (_) {
    throw const ParseException('TikTok 页面数据损坏，请重试');
  }

  final scope = _mapOf(root, '__DEFAULT_SCOPE__');
  final detail = scope == null
      ? null
      : _mapOf(scope, 'webapp.video-detail');
  final itemInfo = detail == null ? null : _mapOf(detail, 'itemInfo');
  final item = itemInfo == null ? null : _mapOf(itemInfo, 'itemStruct');
  if (item == null) {
    throw const ParseException('TikTok 未找到作品数据（可能已删除或需登录）');
  }

  final title = _strOf(item, 'desc') ?? '未知标题';
  final authorMap = _mapOf(item, 'author');
  final author =
      (authorMap == null
          ? null
          : (_strOf(authorMap, 'nickname') ??
                _strOf(authorMap, 'uniqueId'))) ??
      '未知作者';
  final video = _mapOf(item, 'video') ?? {};
  final duration = _intOf(video, 'duration');
  final thumbnail = _strOf(video, 'cover');

  final formats = <VideoFormat>[];
  final downloadAddr = _strOf(video, 'downloadAddr');
  final playAddr = _strOf(video, 'playAddr');
  if (downloadAddr != null) {
    formats.add(
      VideoFormat(quality: '无水印·下载', url: downloadAddr, ext: 'mp4'),
    );
  }
  if (playAddr != null && playAddr != downloadAddr) {
    formats.add(VideoFormat(quality: '播放', url: playAddr, ext: 'mp4'));
  }
  // 兼容部分地区字段名差异
  final playAddrList = _listOf(video, 'playAddrList');
  if (formats.isEmpty && playAddrList != null) {
    for (final e in playAddrList) {
      if (e is String && e.isNotEmpty) {
        formats.add(VideoFormat(quality: '播放', url: e, ext: 'mp4'));
      }
    }
  }
  if (formats.isEmpty) {
    final isImagePost =
        (_listOf(item, 'imagePost') ?? _listOf(video, 'images')) != null;
    throw ParseException(
      isImagePost ? '暂不支持 TikTok 图集作品' : '未获取到可用的视频下载链接',
    );
  }

  return ParseResult(
    title: title,
    author: author,
    platform: 'tiktok',
    duration: duration,
    thumbnail: thumbnail,
    formats: formats,
  );
}

/// 从错误响应体里捞服务器给出的原因
///（抖音经常在 4xx 的 JSON 里写 status_msg，之前直接丢掉了）。
String? _serverMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    for (final k in ['status_msg', 'message', 'msg', 'error_msg']) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final code = data['status_code'];
    if (code != null) return 'status_code=$code';
    return null;
  }
  if (data is String) {
    final t = data.trim();
    // HTML 错误页没有信息量，只收纯文本短消息
    if (t.isNotEmpty && t.length < 300 && !t.startsWith('<')) return t;
  }
  return null;
}

/// 抖音详情接口阶段的错误：401/403/418 几乎总是缺 Cookie 或被风控，
/// 直接告诉用户去粘贴 Cookie，而不是泛泛的“网络错误”。
Never _detailError(DioException e) {
  final status = e.response?.statusCode;
  final serverMsg = _serverMessage(e);
  final suffix = serverMsg != null ? '（服务器：$serverMsg）' : '';
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      throw const NetworkException('抖音解析超时，请重试');
    case DioExceptionType.connectionError:
      throw const NetworkException('无法连接抖音，请检查网络或代理设置');
    default:
      if (status == 401 || status == 403 || status == 418) {
        throw ParseException(
          '抖音拒绝了本次请求（$status）$suffix：请到“设置 → Cookie”粘贴浏览器 Cookie 后重试；'
          '若已粘贴仍失败，可能是签名参数过期，等更新',
        );
      }
      throw NetworkException(
        '抖音网络错误${status != null ? '（$status）' : ''}$suffix，请重试',
        statusCode: status,
      );
  }
}

Never _networkError(DioException e, String platform) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      throw NetworkException('$platform 解析超时，请重试');
    case DioExceptionType.connectionError:
      throw NetworkException('无法连接$platform，请检查网络或代理设置');
    default:
      throw NetworkException(
        '$platform 网络错误${e.response?.statusCode != null ? '（${e.response!.statusCode}）' : ''}，请重试',
        statusCode: e.response?.statusCode,
      );
  }
}
