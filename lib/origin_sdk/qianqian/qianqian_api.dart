import "dart:convert";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";

import "../origin_types.dart";

/// 千千音乐接口错误（类型化，UI 决定提示）
class QianqianApiError implements Exception {
  final String message;
  const QianqianApiError(this.message);

  @override
  String toString() => message;
}

/// 千千音乐音源（批次 3，91q.com）：MD5 签名接口 + tracklink 直链取流。
/// - 可播口径 isVip=0（非 VIP 全量可播，免费内容比 QQ 多）
/// - 榜单：官方新歌榜走 /v1/bd/list（bdid 为页面实测值，历史稳定；
///   toplist 列表页是 NUXT SSR 无法可靠解析，故只硬编码精选单榜）
class QianqianApi implements OriginService {
  /// 榜单卡 key 前缀（广场定义表与 OriginService.getChartHits 共用约定）
  static const chartKeyPrefix = "qianqian:";

  /// 新歌榜 bdid（2026-10 实测；bd/list 详情可独立验证）
  static const newSongChartBdid = "257851";

  static const _appid = "16073360";
  static const _secret = "0b50b02fd0d73a9c4c8c3a781c30845f";

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://music.91q.com/",
        "from": "web",
      },
    ),
  );

  /// 接口签名（老插件同款算法）：参数按 key 排序拼 k=v&…，尾拼 secret 取 MD5
  Map<String, String> _signedParams(Map<String, String> params) {
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    final all = {...params, "timestamp": timestamp};
    final keys = all.keys.toList()..sort();
    final raw =
        keys.map((k) => "$k=${all[k]}").join("&") + _secret;
    final sign = md5.convert(utf8.encode(raw)).toString();
    return {...all, "sign": sign};
  }

  @override
  Future<SearchResponse> search(SearchParams params) async {
    final keyword = params.keyword.trim();
    if (keyword.isEmpty) {
      return QianqianSearchResponse(
        current: params.page,
        total: 0,
        pageSize: params.pageSize ?? 20,
        data: const [],
      );
    }
    final size = params.pageSize ?? 20;
    try {
      final response = await _dio.get(
        "https://music.91q.com/v1/search",
        queryParameters: _signedParams({
          "appid": _appid,
          "type": "1",
          "word": keyword,
          "pageNo": "${params.page}",
          "pageSize": "$size",
        }),
      );
      final respData = _map(response.data);
      final data = respData is Map ? respData["data"] : null;
      final tracks =
          data is Map ? data["typeTrack"] as List? ?? const [] : const [];
      final items = parseQianqianSongs(tracks);
      final total = _asInt(data is Map ? data["total"] : null);
      return QianqianSearchResponse(
        current: params.page,
        total: total > 0 ? total : items.length,
        pageSize: size,
        data: items,
      );
    } on QianqianApiError {
      rethrow;
    } catch (e) {
      throw QianqianApiError("千千搜索失败：$e");
    }
  }

  @override
  Future<List<ChartHit>?> getChartHits(String chartKey) async {
    if (!chartKey.startsWith(chartKeyPrefix)) return null;
    final bdid = chartKey.substring(chartKeyPrefix.length);
    if (bdid.isEmpty) return null;
    try {
      final response = await _dio.get(
        "https://music.91q.com/v1/bd/list",
        queryParameters: _signedParams({"bdid": bdid, "appid": _appid}),
      );
      final respData = _map(response.data);
      final data = respData is Map ? respData["data"] : null;
      final tracks =
          data is Map ? data["result"] as List? ?? const [] : const [];
      final hits = parseQianqianChartHits(tracks);
      if (hits.isNotEmpty) return hits;
      throw QianqianApiError("千千榜单返回空（$chartKey）");
    } on QianqianApiError {
      rethrow;
    } catch (e) {
      throw QianqianApiError("千千榜单拉取失败（$chartKey）：$e");
    }
  }

  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    final tsid = id.startsWith(chartKeyPrefix)
        ? id.substring(chartKeyPrefix.length)
        : id;
    if (tsid.isEmpty) throw const QianqianApiError("千千歌曲 ID 不正确");
    try {
      final response = await _dio.get(
        "https://music.91q.com/v1/song/tracklink",
        queryParameters: _signedParams({"TSID": tsid, "appid": _appid}),
      );
      final respData = _map(response.data);
      final data = respData is Map ? respData["data"] : null;
      final path = data is Map ? data["path"] : null;
      if (path is! String || path.isEmpty) {
        throw const QianqianApiError("千千未返回可用播放地址（版权受限曲目）");
      }
      return MusicUrl(url: path, contentType: "audio/mpeg");
    } on QianqianApiError {
      rethrow;
    } catch (e) {
      throw QianqianApiError("千千取流失败：$e");
    }
  }

  @override
  Future<List<SearchItem>> hotSongs() async => const [];

  @override
  Future<SearchItem> searchDetail(String id) async {
    // 千千条目即单曲，无多 P/合集详情；搜索页不会调用（同酷我/网易约定）
    throw const QianqianApiError("千千暂不支持详情接口");
  }

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  /// 响应可能是未解码的 JSON 字符串，统一转 Map
  dynamic _map(dynamic data) => data is String ? jsonDecode(data) : data;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse("$value") ?? 0;
}

/// 可播口径：isVip=0 / 缺省（JSON 数字 0；老响应可能出现 bool）
bool isQianqianPlayable(Map track) {
  final vip = track["isVip"];
  return vip == null || vip == 0 || vip == false;
}

/// 千千时长统一成秒（实测接口给秒）
int qianqianDurationToSec(dynamic raw) {
  if (raw is num) return raw.round();
  return int.tryParse("$raw") ?? 0;
}

/// 千千搜索单条 → 统一 SearchItem（纯函数便于测试）；无 TSID/歌名的脏数据返回 null
SearchItem? qianqianSongToSearchItem(Map track) {
  final id = "${track["id"] ?? track["assetId"] ?? ""}";
  final title = "${track["title"] ?? ""}".trim();
  if (id.isEmpty || title.isEmpty) return null;
  final artists = track["artist"] as List? ?? const [];
  final author = artists
      .whereType<Map>()
      .map((a) => "${a["name"] ?? ""}")
      .where((n) => n.isNotEmpty)
      .join("/");
  return SearchItem(
    id: "qianqian:$id",
    cover: "${track["pic"] ?? ""}",
    name: title,
    duration: qianqianDurationToSec(track["duration"]),
    author: author,
    origin: OriginType.qianqian,
    isSeasonDisplay: false,
    type: SearchType.music,
  );
}

/// 搜索结果解析（纯函数）：过滤 VIP 与脏数据
List<SearchItem> parseQianqianSongs(List list) {
  final items = <SearchItem>[];
  for (final track in list) {
    if (track is! Map || !isQianqianPlayable(track)) continue;
    final item = qianqianSongToSearchItem(track);
    if (item != null) items.add(item);
  }
  return items;
}

/// 榜单（bd/list 的 result）解析（纯函数）：同口径过滤，封顶 30 条
List<ChartHit> parseQianqianChartHits(List tracks) {
  final hits = <ChartHit>[];
  for (final track in tracks) {
    if (track is! Map || !isQianqianPlayable(track)) continue;
    final item = qianqianSongToSearchItem(track);
    if (item == null) continue;
    hits.add(ChartHit(name: item.name, artist: item.author, item: item));
    if (hits.length >= 30) break;
  }
  return hits;
}

/// 搜索响应（OriginService 只要求 SearchResponse 抽象，提供具体实现）
class QianqianSearchResponse extends SearchResponse {
  const QianqianSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
  });
}
