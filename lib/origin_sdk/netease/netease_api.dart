import "dart:convert";

import "package:dio/dio.dart";

import "../origin_types.dart";

/// 网易云接口错误（类型化，UI 决定提示；不依赖其他源错误类型）
class NeteaseApiError implements Exception {
  final String message;
  const NeteaseApiError(this.message);

  @override
  String toString() => message;
}

/// 网易云音源（D7 之外的第三音源，批次 2）：
/// - 搜索/榜单走免加密老接口（weapi 加密版留作漂移后备，2026-10 实测免加密可用）
/// - 取流 outer/url 302 直链：仅免费歌（fee=0/8）返回音频，VIP/下架歌会 302 到
///   HTML 兜底页——搜索与榜单都必须按 fee 过滤，这是本源的可用性口径
/// 网易云音源（D7 之外的第三音源，批次 2）：
/// - 搜索/榜单走免加密老接口（weapi 加密版留作漂移后备，2026-10 实测免加密可用）
/// - 取流 outer/url 302 直链：仅免费歌（fee=0/8）返回音频，VIP/下架歌会 302 到
///   HTML 兜底页——搜索与榜单都必须按 fee 过滤，这是本源的可用性口径
///
/// 注意：老接口响应 content-type 非 JSON，Dio 不自动解码，须手动 jsonDecode
class NeteaseApi implements OriginService {
  /// 榜单卡 key 前缀（广场定义表与 OriginService.getChartHits 共用约定）
  static const chartKeyPrefix = "netease:";

  /// 官方榜 playlist id（免加密 playlist/detail 拉取；飙升/热歌为 2026-10 实测值）
  static const surgeChartId = "19723756";
  static const hotChartId = "3779629";

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://music.163.com/",
        // 老接口匿名可访问，带占位 cookie 更稳（实测口径，非登录态）
        "cookie": "NMTID=00O0YWlSDl0nRIvF3TTFpx0ZgOVzZ8",
      },
    ),
  );

  @override
  Future<SearchResponse> search(SearchParams params) async {
    final keyword = params.keyword.trim();
    if (keyword.isEmpty) {
      return NeteaseSearchResponse(
        current: params.page,
        total: 0,
        pageSize: params.pageSize ?? 30,
        data: const [],
      );
    }
    final size = params.pageSize ?? 30;
    try {
      final response = await _dio.get(
        "https://music.163.com/api/search/get/web",
        queryParameters: {
          "s": keyword,
          "type": "1",
          "offset": "${(params.page - 1) * size}",
          "limit": "$size",
        },
      );
      final data = _map(response.data);
      final result = data["result"];
      final songs = result is Map ? result["songs"] as List? ?? const [] : const [];
      final items = parseNeteaseSongs(songs);
      final total = _asInt(result is Map ? result["songCount"] : null);
      return NeteaseSearchResponse(
        current: params.page,
        total: total > 0 ? total : items.length,
        pageSize: size,
        data: items,
      );
    } on NeteaseApiError {
      rethrow;
    } catch (e) {
      throw NeteaseApiError("网易云搜索失败：$e");
    }
  }

  @override
  Future<List<ChartHit>?> getChartHits(String chartKey) async {
    if (!chartKey.startsWith(chartKeyPrefix)) return null;
    final pid = chartKey.substring(chartKeyPrefix.length);
    if (pid.isEmpty) return null;
    try {
      final response = await _dio.get(
        "https://music.163.com/api/v3/playlist/detail",
        queryParameters: {"id": pid, "n": "5000"},
        options: Options(
          headers: {
            "Referer": "https://y.music.163.com/",
            "Origin": "https://y.music.163.com",
          },
        ),
      );
      final data = _map(response.data);
      final playlist = data["playlist"];
      final tracks =
          playlist is Map ? playlist["tracks"] as List? ?? const [] : const [];
      final hits = parseNeteaseChartHits(tracks);
      if (hits.isNotEmpty) return hits;
      throw NeteaseApiError("网易云榜单返回空（$chartKey）");
    } on NeteaseApiError {
      rethrow;
    } catch (e) {
      throw NeteaseApiError("网易云榜单拉取失败（$chartKey）：$e");
    }
  }

  @override
  Future<List<SearchItem>> hotSongs() async => const [];

  @override
  Future<SearchItem> searchDetail(String id) async {
    // 网易条目即单曲，无多 P/合集详情；搜索页不会调用（同酷我约定）
    throw const NeteaseApiError("网易云暂不支持详情接口");
  }

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    final rid = id.startsWith(chartKeyPrefix)
        ? id.substring(chartKeyPrefix.length)
        : id;
    if (rid.isEmpty || int.tryParse(rid) == null) {
      throw const NeteaseApiError("网易云歌曲 ID 不正确");
    }
    // 302 跳转由播放内核跟随；VIP 歌（过滤漏网）会跳 HTML 兜底页，
    // 播放引擎报错走现有失败回退链
    return MusicUrl(
      url: "https://music.163.com/song/media/outer/url?id=$rid.mp3",
      contentType: "audio/mpeg",
    );
  }

  /// 老接口响应可能是未解码的 JSON 字符串（content-type 非 JSON），统一转 Map
  dynamic _map(dynamic data) {
    if (data is String) {
      return jsonDecode(data);
    }
    return data;
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse("$value") ?? 0;
}

/// fee 可播口径：0=免费、8=低音质免费；其余（1=VIP、4=购专等）outer/url 拿不到音频
bool isNeteasePlayable(Map song) {
  final fee = song["fee"];
  return fee is num && (fee == 0 || fee == 8);
}

/// 网易时长统一成秒（接口给毫秒）
int neteaseDurationToSec(dynamic raw) {
  if (raw is num) return raw ~/ 1000;
  final ms = int.tryParse("$raw") ?? 0;
  return ms ~/ 1000;
}

/// 网易搜索单条 → 统一 SearchItem（纯函数便于测试）；无 id/歌名的脏数据返回 null。
/// 兼容两种形态字段：老接口 artists/album，v3 playlist/detail 的 ar/al（实测榜单用 v3）
SearchItem? neteaseSongToSearchItem(Map song) {
  final id = "${song["id"] ?? ""}";
  final name = "${song["name"] ?? ""}".trim();
  if (id.isEmpty || int.tryParse(id) == null || name.isEmpty) return null;
  final artists = (song["ar"] ?? song["artists"]) as List? ?? const [];
  final artist = artists.isNotEmpty
      ? "${(artists.first as Map)["name"] ?? ""}"
      : "";
  final album = (song["al"] ?? song["album"]) as Map?;
  final cover = "${album?["picUrl"] ?? ""}";
  return SearchItem(
    id: "netease:$id",
    cover: cover,
    name: name,
    duration: neteaseDurationToSec(song["duration"]),
    author: artist,
    origin: OriginType.netease,
    isSeasonDisplay: false,
    type: SearchType.music,
  );
}

/// 搜索结果解析（纯函数）：过滤 VIP/不可播与脏数据
List<SearchItem> parseNeteaseSongs(List list) {
  final items = <SearchItem>[];
  for (final song in list) {
    if (song is! Map || !isNeteasePlayable(song)) continue;
    final item = neteaseSongToSearchItem(song);
    if (item != null) items.add(item);
  }
  return items;
}

/// 榜单（playlist/detail 的 tracks）解析（纯函数）：同口径过滤，封顶 30 条
List<ChartHit> parseNeteaseChartHits(List tracks) {
  final hits = <ChartHit>[];
  for (final track in tracks) {
    if (track is! Map || !isNeteasePlayable(track)) continue;
    final item = neteaseSongToSearchItem(track);
    if (item == null) continue;
    hits.add(ChartHit(name: item.name, artist: item.author, item: item));
    if (hits.length >= 30) break;
  }
  return hits;
}

/// 搜索响应（OriginService 只要求 SearchResponse 抽象，提供具体实现）
class NeteaseSearchResponse extends SearchResponse {
  const NeteaseSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
  });
}
