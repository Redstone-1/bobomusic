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

/// 请求、风控归一和一次鉴权恢复；SDK 不直接提示 UI。
class BiliApi implements OriginService {
  final Dio _dio;
  final BiliAuth auth;
  final _playurlCache = TtlLruCache<MusicUrl>(
    maxEntries: 8,
    ttl: const Duration(minutes: 5),
  );

  BiliApi({BiliAuth? authOverride, Dio? dioOverride})
      : _dio = dioOverride ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        auth = authOverride ?? BiliAuth() {
    _dio.options.headers["User-Agent"] = _userAgent;
    _dio.options.headers["Referer"] = _referer;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // playurl 始终不带 cookie，包括重试时，避免继承搜索请求的身份头。
        if (options.uri.path.startsWith("/x/player/wbi/playurl")) {
          options.headers
              .removeWhere((key, _) => key.toLowerCase() == "cookie");
        } else {
          final cookie = auth.cookieHeader();
          if (cookie != null) options.headers["cookie"] = cookie;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final body = response.data;
        if (body is! Map) {
          handler.next(response);
          return;
        }
        final code = body["code"];
        final data = body["data"];
        final risk = data is Map && data["v_voucher"] != null;
        // 风控可能返回 code=0，必须先识别 voucher，不能送进正常列表解析。
        if (risk || (code is int && code != 0)) {
          final error = BiliApiRejectError(
            risk ? "请求触发风控，请稍后重试" : "请求被拒绝：${body["message"]}",
            code: code is int ? code : 0,
            riskControl: risk,
            cause: body,
          );
          handler.reject(DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: error,
          ));
          return;
        }
        handler.next(response);
      },
    ));
  }

  @override
  Future<SearchResponse> search(SearchParams params) => _query(
        "https://api.bilibili.com/x/web-interface/wbi/search/type",
        {
          "search_type": "video",
          "keyword": params.keyword,
          "page": params.page.toString(),
          "pagesize": "20",
        },
        (data) => BiliSearchResponse.fromJson(data),
      );

  @override
  Future<SearchItem> searchDetail(String id) {
    final biliid = BiliId.unicode(id);
    return _query(
      "https://api.bilibili.com/x/web-interface/view",
      {"aid": biliid.aid, "bvid": biliid.bvid},
      (data) => BiliSearchItem.fromJson(data["data"]),
    );
  }

  Future<BiliSearchSeasonItem?> searchSeason(int mid, int seasonId) => _query(
        "https://api.bilibili.com/x/polymer/web-space/seasons_archives_list",
        {
          "mid": "$mid",
          "season_id": "$seasonId",
          "page_num": "1",
          "page_size": "30",
        },
        (data) => BiliSearchSeasonItem.fromJson(data["data"]),
      );

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) => _query(
        "https://s.search.bilibili.com/main/suggest",
        {"term": keyword},
        (data) {
          final decoded = data is String ? jsonDecode(data) : data;
          final tags = decoded["result"]["tag"] as List;
          return [
            for (final tag in tags)
              SearchSuggestItem(name: tag["name"], value: tag["value"]),
          ];
        },
      );

  @override
  Future<List<SearchItem>> hotSongs() async => const [];

  @override
  Future<List<ChartHit>?> getChartHits(String chartKey) async => null;

  @override
  Future<MusicUrl> getMusicUrl(String id, {bool forceRefresh = false}) async {
    if (forceRefresh) _playurlCache.remove(id);
    if (!forceRefresh) {
      final cached = _playurlCache.get(id);
      if (cached != null) return cached;
    }
    final biliid = BiliId.unicode(id);
    var cid = biliid.cid;
    if (cid == null || cid.isEmpty) {
      final detail = await searchDetail(id);
      final healedId = detail.musicList?.isNotEmpty == true
          ? detail.musicList!.first.id
          : detail.id;
      cid = BiliId.unicode(healedId).cid;
      if (cid == null || cid.isEmpty) {
        throw BiliInvalidIdError("歌曲 ID 不正确：无法补齐 CID（$id）");
      }
    }
    final musicUrl = await _query(
      "https://api.bilibili.com/x/player/wbi/playurl",
      {"avid": biliid.aid, "bvid": biliid.bvid, "cid": cid, "fnval": "16"},
      (data) => parsePlayUrl(Map<String, dynamic>.from(data["data"])),
    );
    _playurlCache.set(id, musicUrl);
    return musicUrl;
  }

  /// 每次重试重新签名；风控/签名失效只重刷一次，普通业务错误不重试。
  Future<T> _query<T>(
    String url,
    Map<String, String> params,
    T Function(dynamic data) parse,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        final query = await _signedQuery(Map.of(params));
        final response = await _guard(
          () => _dio.get(url, queryParameters: query),
        );
        return await _guard(() async => parse(response.data));
      } on BiliApiRejectError catch (e) {
        if (attempt != 0 ||
            !(e.riskControl ||
                e.code == -403 ||
                e.code == -352 ||
                e.code == -412)) {
          rethrow;
        }
        _playurlCache.clear();
        await auth.refresh();
      } on BiliHttpError catch (e) {
        if (attempt != 0 || e.statusCode != 412) rethrow;
        _playurlCache.clear();
        await auth.refresh();
      }
    }
  }

  Future<Map<String, String>> _signedQuery(Map<String, String> params) async {
    await auth.ensure();
    final sign = auth.signData;
    if (sign == null) throw const BiliAuthError("签名密钥缺失");
    return Map<String, String>.from(
      encWbi(params, sign.imgKey, sign.subKey),
    );
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on BiliApiError {
      rethrow;
    } on DioException catch (e) {
      final inner = e.error;
      if (inner is BiliApiError) throw inner;
      if (e.response != null) {
        throw BiliHttpError(
          "请求失败（HTTP ${e.response!.statusCode}），请稍后重试",
          statusCode: e.response!.statusCode,
          cause: e,
        );
      }
      throw BiliNetworkError("网络请求失败，请检查网络后重试", cause: e);
    } catch (e) {
      throw BiliParseError("响应格式变化，请稍后重试", cause: e);
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
  final backupUrl =
      (best["backupUrl"] as List?)?.whereType<String>().firstOrNull;
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

  TtlLruCache(
      {required this.maxEntries, required this.ttl, DateTime Function()? now})
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

  void remove(String key) => _entries.remove(key);
}

class _CacheEntry<V> {
  final V value;
  final DateTime expiresAt;

  _CacheEntry(this.value, this.expiresAt);
}
