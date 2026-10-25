import "dart:convert";

import "package:dio/dio.dart";

import "../origin_types.dart";
import "bili_api_error.dart";
import "bili_auth.dart";
import "sign.dart";
import "types.dart";
import "utils.dart";

const _userAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const _referer = "https://www.bilibili.com/";

/// B 站 API（S2.1 拆分）：请求与解析层，依赖 [BiliAuth] 提供鉴权材料
/// - 单一 Dio 实例（S2.2：消灭 getBNut 每次 new Dio）
/// - 对外只抛 [BiliApiError] 子类；playurl 结果走内存 LRU 短缓存（S2.2）
class BiliApi implements OriginService {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  final BiliAuth auth;

  /// playurl LRU 短缓存：B 站直链自身有时效（~数小时），5 分钟足够消灭冷播重复 RTT
  final _playurlCache = TtlLruCache<MusicUrl>(maxEntries: 8, ttl: const Duration(minutes: 5));

  BiliApi({BiliAuth? authOverride}) : auth = authOverride ?? BiliAuth() {
    _dio.options.headers["User-Agent"] = _userAgent;
    _dio.options.headers["Referer"] = _referer;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // playurl 不带 cookie（B 站风控特判，继承旧版行为）
          if (!options.uri.path.startsWith("/x/player/wbi/playurl")) {
            final cookie = auth.cookieHeader();
            if (cookie != null) options.headers["cookie"] = cookie;
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.realUri.toString().contains("x/web-interface/nav")) {
            return handler.next(response);
          }
          if ((response.statusCode ?? 0) < 200 ||
              (response.statusCode ?? 0) > 300) {
            throw BiliHttpError(
              "请求失败 ${response.statusCode} ${response.statusMessage}",
              statusCode: response.statusCode,
              cause: response.data,
            );
          }
          if (response.data is! Map) return handler.next(response);

          final code = response.data["code"];
          final message = response.data["message"];
          final resData = response.data["data"];
          if (code != 0) {
            throw BiliApiRejectError(
              "请求被拒绝：$message",
              code: code,
              riskControl: resData is Map && resData["v_voucher"] != null,
              cause: response.data,
            );
          }
          return handler.next(response);
        },
      ),
    );
  }

  @override
  Future<SearchResponse> search(SearchParams params) async {
    final query = await _signedQuery({
      "search_type": "video",
      "keyword": params.keyword,
      "page": params.page.toString(),
      "pagesize": "20",
    });
    final apiPath = Uri.parse(
      "https://api.bilibili.com/x/web-interface/wbi/search/type",
    ).replace(queryParameters: query).toString();
    // S2.1：不再静默吞错返回空结果——无结果与请求失败由调用方区分
    final response = await _guard(() => _dio.get(apiPath));
    return BiliSearchResponse.fromJson(response.data);
  }

  @override
  Future<SearchItem> searchDetail(String id) async {
    final biliid = BiliId.unicode(id);
    final query = await _signedQuery({
      "aid": biliid.aid,
      "bvid": biliid.bvid,
    });
    final apiPath = Uri.parse(
      "https://api.bilibili.com/x/web-interface/view",
    ).replace(queryParameters: query).toString();
    final response = await _guard(() => _dio.get(apiPath));
    return BiliSearchItem.fromJson(response.data["data"]);
  }

  /// 搜索视频所在系列或合集
  Future<BiliSearchSeasonItem?> searchSeason(int mid, int seasonId) async {
    final query = await _signedQuery({
      "mid": "$mid",
      "season_id": "$seasonId",
      "page_num": "1",
      "page_size": "30",
    });
    final apiPath = Uri.parse(
      "https://api.bilibili.com/x/polymer/web-space/seasons_archives_list",
    ).replace(queryParameters: query).toString();
    final response = await _guard(() => _dio.get(apiPath));
    return BiliSearchSeasonItem.fromJson(response.data["data"]);
  }

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async {
    final query = await _signedQuery({"term": keyword});
    final response = await _guard(
      () => _dio.get(
        "https://s.search.bilibili.com/main/suggest",
        queryParameters: query,
      ),
    );
    final data =
        response.data is String ? jsonDecode(response.data) : response.data;
    try {
      final List<dynamic> tags = data["result"]["tag"];
      return [
        for (final t in tags) SearchSuggestItem(name: t["name"], value: t["value"]),
      ];
    } catch (e) {
      throw BiliParseError("搜索建议响应结构不符", cause: e);
    }
  }

  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    // LRU 命中直接秒回（冷播省一次签名+RTT）
    final cached = _playurlCache.get(id);
    if (cached != null) return cached;

    final biliid = BiliId.unicode(id);
    if (biliid.cid == null || biliid.cid == "") {
      throw BiliInvalidIdError("歌曲 ID 不正确：缺少 CID（$id）");
    }
    final query = await _signedQuery({
      "avid": biliid.aid,
      "bvid": biliid.bvid,
      "cid": biliid.cid!,
      "fnval": "16",
    });
    final uri = Uri.parse(
      "https://api.bilibili.com/x/player/wbi/playurl",
    ).replace(queryParameters: query).toString();
    final response = await _guard(() => _dio.get(uri));
    final musicUrl = parsePlayUrl(response.data["data"]);
    _playurlCache.set(id, musicUrl);
    return musicUrl;
  }

  /// WBI 签名查询串；鉴权材料缺失 → [BiliAuthError]
  Future<Map<String, String>> _signedQuery(Map<String, String> params) async {
    await auth.ensure();
    final sign = auth.signData;
    if (sign == null) {
      throw const BiliAuthError("签名密钥缺失（ensure 未生效）");
    }
    return Map<String, String>.from(
      encWbi(params, sign.imgKey, sign.subKey),
    );
  }

  /// 统一错误包装：拦截器抛出的 BiliApiError 原样上抛，Dio 层错误类型化
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on BiliApiError {
      rethrow;
    } on DioException catch (e) {
      final inner = e.error;
      if (inner is BiliApiError) throw inner;
      throw BiliNetworkError("网络请求失败（${e.type.name}）", cause: e);
    } catch (e) {
      throw BiliParseError("响应处理失败", cause: e);
    }
  }
}

/// playurl 响应解析（纯函数，特征测试锁定）：dash 音频按 bandwidth 取最高，
/// backupUrl 首项保留为备用直链（主 CDN 异常降级，§5.3-4）
/// 注意：B 站 dash 音频 contentType 按 video/mp4 声明（实际 m4a），换播放内核时留意
MusicUrl parsePlayUrl(Map<String, dynamic> data) {
  final List<dynamic> audioList =
      data["dash"]?["audio"]?.toList() ?? <dynamic>[];
  if (audioList.isEmpty) {
    throw const BiliParseError("playurl 无可用音频流（dash.audio 为空）");
  }
  audioList.sort((a, b) => b["bandwidth"].compareTo(a["bandwidth"]));
  final best = audioList[0];
  final backupUrl = (best["backupUrl"] as List?)
      ?.whereType<String>()
      .firstOrNull;
  return MusicUrl(
    url: best["baseUrl"],
    headers: {"Referer": _referer},
    backupUrl: backupUrl,
  );
}

/// 带 TTL 与 LRU 淘汰的内存缓存（时间可注入，便于特征测试）
class TtlLruCache<V> {
  final int maxEntries;
  final Duration ttl;
  final DateTime Function() _now;

  final _entries = <String, _CacheEntry<V>>{};

  TtlLruCache({required this.maxEntries, required this.ttl, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  V? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_now().isAfter(entry.expiresAt)) return null; // 过期即弃
    _entries[key] = entry; // 触摸续命（LRU）
    return entry.value;
  }

  void set(String key, V value) {
    _entries.remove(key);
    _entries[key] = _CacheEntry(value, _now().add(ttl));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

class _CacheEntry<V> {
  final V value;
  final DateTime expiresAt;

  _CacheEntry(this.value, this.expiresAt);
}
