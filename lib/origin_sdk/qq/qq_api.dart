import "dart:convert";

import "package:dio/dio.dart";

import "../origin_types.dart";

/// QQ 音乐接口错误（类型化，UI 决定提示）
class QqApiError implements Exception {
  final String message;
  const QqApiError(this.message);

  @override
  String toString() => message;
}

/// QQ 音乐音源（批次 3）：musicu.fcg 统一入口，免登录匿名访问。
/// - 搜索 DoSearchForQQMusicDesktop；取流 vkey.GetVkeyServer 拼直链
/// - 只有免费歌（pay.pay_play=0）出 purl，VIP/版权歌为空——搜索必须过滤
/// - 榜单卡未上线（QQ 免费条目少），qq: 前缀与 getChartHits 预留
class QqApi implements OriginService {
  /// 榜单卡 key 前缀（预留；当前无 QQ 榜单卡，getChartHits 返回 null）
  static const chartKeyPrefix = "qq:";

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://y.qq.com/",
        "Cookie": "uin=",
      },
    ),
  );

  @override
  Future<SearchResponse> search(SearchParams params) async {
    final keyword = params.keyword.trim();
    if (keyword.isEmpty) {
      return QqSearchResponse(
        current: params.page,
        total: 0,
        pageSize: params.pageSize ?? 30,
        data: const [],
      );
    }
    final size = params.pageSize ?? 30;
    try {
      // musicu.fcg 的 POST 形式会间歇性被风控（req_1.code=2001，实测 2026-10），
      // GET + data 查询参数的形式稳定可用（与 vkey 取流同款），故统一走 GET
      final response = await _dio.get(
        "https://u.y.qq.com/cgi-bin/musicu.fcg",
        queryParameters: {
          "g_tk": "5381",
          "loginUin": "",
          "hostUin": "0",
          "format": "json",
          "platform": "yqq.json",
          "needNewCode": "0",
          "data": jsonEncode({
            "req_1": {
              "method": "DoSearchForQQMusicDesktop",
              "module": "music.search.SearchCgiService",
              "param": {
                "num_per_page": size,
                "page_num": params.page,
                "query": keyword,
                "search_type": 0,
              },
            },
          }),
        },
      );
      final data = _map(response.data);
      final reqData = data["req_1"] is Map ? data["req_1"]["data"] : null;
      final body = reqData is Map ? reqData["body"] : null;
      final songNode = body is Map ? body["song"] : null;
      final songs =
          songNode is Map ? songNode["list"] as List? ?? const [] : const [];
      final items = parseQqSongs(songs);
      final meta = reqData is Map ? reqData["meta"] : null;
      final total = _asInt(meta is Map ? meta["sum"] : null);
      return QqSearchResponse(
        current: params.page,
        total: total > 0 ? total : items.length,
        pageSize: size,
        data: items,
      );
    } on QqApiError {
      rethrow;
    } catch (e) {
      throw QqApiError("QQ 音乐搜索失败：$e");
    }
  }

  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    final mid =
        id.startsWith(chartKeyPrefix) ? id.substring(chartKeyPrefix.length) : id;
    if (mid.isEmpty) throw const QqApiError("QQ 歌曲 ID 不正确");
    try {
      final response = await _dio.get(
        "https://u.y.qq.com/cgi-bin/musicu.fcg",
        queryParameters: {
          "-": "getplaysongvkey",
          "g_tk": "5381",
          "loginUin": "",
          "hostUin": "0",
          "format": "json",
          "platform": "yqq.json",
          "needNewCode": "0",
          "data": jsonEncode({
            "req_0": {
              "module": "vkey.GetVkeyServer",
              "method": "CgiGetVkey",
              "param": {
                "filename": ["M800$mid.mp3"],
                "guid": _randomGuid(),
                "songmid": [mid],
                "songtype": [0],
                "uin": "",
                "loginflag": 1,
                "platform": "20",
              },
            },
            "comm": {
              "uin": "",
              "format": "json",
              "ct": 19,
              "cv": 0,
              "authst": "",
            },
          }),
        },
      );
      final url = parseQqVkey(_map(response.data));
      if (url == null || url.isEmpty) {
        throw QqApiError("QQ 未返回可用播放地址（VIP/版权受限曲目）");
      }
      return MusicUrl(url: url, contentType: "audio/mpeg");
    } on QqApiError {
      rethrow;
    } catch (e) {
      throw QqApiError("QQ 取流失败：$e");
    }
  }

  @override
  Future<List<SearchItem>> hotSongs() async => const [];

  // 榜单卡未上线（免费条目少）；qq: 前缀预留，当前不支持任何 key
  @override
  Future<List<ChartHit>?> getChartHits(String chartKey) async => null;

  @override
  Future<SearchItem> searchDetail(String id) async {
    // QQ 条目即单曲，无多 P/合集详情；搜索页不会调用（同酷我/网易约定）
    throw const QqApiError("QQ 音乐暂不支持详情接口");
  }

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  /// vkey guid：随机数字串即可（老插件同款做法，无强校验）
  static String _randomGuid() =>
      (DateTime.now().microsecondsSinceEpoch % 100000000).toString();

  /// musicu.fcg 响应可能是未解码的 JSON 字符串（content-type 非 JSON），统一转 Map
  dynamic _map(dynamic data) => data is String ? jsonDecode(data) : data;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse("$value") ?? 0;
}

/// 免费可播口径：pay.pay_play=0（新）或 payplay=0（旧字段），其余为 VIP/版权受限
bool isQqPlayable(Map song) {
  final pay = song["pay"];
  if (pay is Map) return pay["pay_play"] == 0 || pay["payplay"] == 0;
  return song["payplay"] == 0;
}

/// QQ 搜索单条 → 统一 SearchItem（纯函数便于测试）；无 mid/歌名的脏数据返回 null
SearchItem? qqSongToSearchItem(Map song) {
  final mid = "${song["mid"] ?? ""}";
  final name = "${song["name"] ?? ""}".trim();
  if (mid.isEmpty || name.isEmpty) return null;
  final singers = song["singer"] as List? ?? const [];
  final author = singers
      .whereType<Map>()
      .map((s) => "${s["name"] ?? ""}")
      .where((n) => n.isNotEmpty)
      .join("/");
  final album = song["album"];
  final albumMid = album is Map ? "${album["mid"] ?? ""}" : "";
  return SearchItem(
    id: "qq:$mid",
    cover: albumMid.isEmpty
        ? ""
        : "https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg",
    name: name,
    duration: _asInt(song["interval"]),
    author: author,
    origin: OriginType.qq,
    isSeasonDisplay: false,
    type: SearchType.music,
  );
}

/// 搜索结果解析（纯函数）：过滤 VIP/版权受限与脏数据
List<SearchItem> parseQqSongs(List list) {
  final items = <SearchItem>[];
  for (final song in list) {
    if (song is! Map || !isQqPlayable(song)) continue;
    final item = qqSongToSearchItem(song);
    if (item != null) items.add(item);
  }
  return items;
}

/// vkey 响应解析（纯函数，特征测试锁定）：
/// sip 列表挑第一个非 ws 前缀域名拼 purl；无 purl（VIP/受限）返回 null
String? parseQqVkey(Map data) {
  final reqNode = data["req_0"];
  final reqData = reqNode is Map ? reqNode["data"] : null;
  if (reqData is! Map) return null;
  final infos = reqData["midurlinfo"] as List? ?? const [];
  final purl = infos.isNotEmpty && infos.first is Map
      ? (infos.first as Map)["purl"]
      : null;
  if (purl is! String || purl.isEmpty) return null;
  final sips = reqData["sip"] as List? ?? const [];
  final domains = sips.whereType<String>().toList();
  final sip = domains.isNotEmpty
      ? domains.firstWhere(
          (s) => !s.startsWith("http://ws"),
          orElse: () => domains.first,
        )
      : "";
  return "$sip$purl";
}

/// 搜索响应（OriginService 只要求 SearchResponse 抽象，提供具体实现）
class QqSearchResponse extends SearchResponse {
  const QqSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
  });
}
