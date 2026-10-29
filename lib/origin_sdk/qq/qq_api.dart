import "dart:convert";

import "package:dio/dio.dart";

import "../origin_types.dart";

enum QqFailure { network, rejected, invalidResponse, unavailable }

class QqApiError implements Exception {
  final String message;
  final QqFailure kind;
  final int? code;

  const QqApiError(
    this.message, {
    this.kind = QqFailure.unavailable,
    this.code,
  });

  @override
  String toString() => message;
}

/// 免费曲目按可用音质降级；接口失败与空播放地址分别处理。
class QqApi implements OriginService {
  static const chartKeyPrefix = "qq:";
  final Dio _dio;
  final _mediaMids = <String, String>{};

  QqApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.options.headers.addAll({
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Referer": "https://y.qq.com/",
      "Cookie": "uin=",
    });
  }

  @override
  Future<SearchResponse> search(SearchParams params) async {
    final keyword = params.keyword.trim();
    final size = params.pageSize ?? 30;
    if (keyword.isEmpty) {
      return QqSearchResponse(
        current: params.page,
        total: 0,
        pageSize: size,
        data: const [],
        hasMore: false,
      );
    }
    try {
      // 过滤后空页不等于原始结果耗尽；每次最多补查三页，避免大量 VIP 结果拖长请求。
      for (var page = params.page;; page++) {
        final data = await _request("req_1", {
          "method": "DoSearchForQQMusicDesktop",
          "module": "music.search.SearchCgiService",
          "param": {
            "num_per_page": size,
            "page_num": page,
            "query": keyword,
            "search_type": 0,
          },
        });
        final body = data["body"];
        final song = body is Map ? body["song"] : null;
        if (song is! Map || song["list"] is! List) {
          throw const QqApiError(
            "QQ 音乐搜索响应格式变化，请稍后重试",
            kind: QqFailure.invalidResponse,
          );
        }
        final raw = song["list"] as List;
        final items = parseQqSongs(raw);
        for (final item in raw.whereType<Map>().where(isQqPlayable)) {
          final mid = item["mid"];
          final file = item["file"];
          final media = file is Map ? file["media_mid"] : null;
          if (mid is String && media is String && media.isNotEmpty) {
            _mediaMids.remove(mid);
            _mediaMids[mid] = media;
            if (_mediaMids.length > 256) {
              _mediaMids.remove(_mediaMids.keys.first);
            }
          }
        }
        final meta = data["meta"];
        final total = _asInt(meta is Map ? meta["sum"] : null);
        final more = raw.isNotEmpty &&
            (total > 0 ? page * size < total : raw.length >= size);
        if (items.isNotEmpty || !more || page - params.page >= 2) {
          return QqSearchResponse(
            current: page,
            total: total,
            pageSize: size,
            data: items,
            hasMore: more,
          );
        }
      }
    } on QqApiError {
      rethrow;
    } catch (e) {
      throw _failure(e, "搜索");
    }
  }

  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    final mid = id.startsWith(chartKeyPrefix)
        ? id.substring(chartKeyPrefix.length)
        : id;
    if (mid.isEmpty) throw const QqApiError("QQ 歌曲 ID 不正确");
    final media = _mediaMids[mid] ?? mid;
    int? lastCode;
    try {
      // 免费播放权限不代表支持 320kbps，先试原音质，再依次降至 MP3/AAC。
      for (final (prefix, extension, mime) in const [
        ("M800", "mp3", "audio/mpeg"),
        ("M500", "mp3", "audio/mpeg"),
        ("C400", "m4a", "audio/mp4"),
      ]) {
        final node = await _request(
            "req_0",
            {
              "module": "vkey.GetVkeyServer",
              "method": "CgiGetVkey",
              "param": {
                "filename": ["$prefix$media.$extension"],
                "guid": _randomGuid(),
                "songmid": [mid],
                "songtype": [0],
                "uin": "",
                "loginflag": 1,
                "platform": "20",
              },
            },
            vkey: true);
        final infos = node["midurlinfo"];
        if (infos is! List || infos.isEmpty || infos.first is! Map) {
          throw const QqApiError(
            "QQ 音乐取流响应格式变化，请稍后重试",
            kind: QqFailure.invalidResponse,
          );
        }
        final info = infos.first as Map;
        final result = info["result"];
        if (result != null && _asInt(result) != 0) {
          lastCode = _asInt(result);
          continue;
        }
        final urls = _qqVkeyUrls({
          "req_0": {"data": node}
        });
        if (urls.isNotEmpty) {
          return MusicUrl(
            url: urls.first,
            backupUrl: urls.length > 1 ? urls[1] : null,
            contentType: mime,
          );
        }
      }
      // 空 purl 不能证明用户需要 VIP，也可能是音质/版权/服务端暂未提供。
      throw QqApiError(
        "QQ 暂无可播放音质，可能存在权限或版权限制，请尝试其他音源",
        code: lastCode,
      );
    } on QqApiError {
      rethrow;
    } catch (e) {
      throw _failure(e, "取流");
    }
  }

  Future<Map> _request(String key, Map request, {bool vkey = false}) async {
    final response = await _dio.get(
      "https://u.y.qq.com/cgi-bin/musicu.fcg",
      queryParameters: {
        if (vkey) "-": "getplaysongvkey",
        "g_tk": "5381",
        "loginUin": "",
        "hostUin": "0",
        "format": "json",
        "platform": "yqq.json",
        "needNewCode": "0",
        "data": jsonEncode({
          key: request,
          if (vkey)
            "comm": {
              "uin": "",
              "format": "json",
              "ct": 19,
              "cv": 0,
              "authst": ""
            },
        }),
      },
    );
    final body = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (body is! Map) {
      throw const QqApiError(
        "QQ 音乐响应格式变化，请稍后重试",
        kind: QqFailure.invalidResponse,
      );
    }
    final node = body[key];
    for (final code in [body["code"], if (node is Map) node["code"]]) {
      if (code != null && code != 0 && code != "0") {
        final value = _asInt(code);
        throw QqApiError(
          value == 2001 ? "QQ 音乐请求被限制，请稍后重试" : "QQ 音乐接口暂时不可用（错误码 $code），请稍后重试",
          kind: QqFailure.rejected,
          code: value,
        );
      }
    }
    if (node is! Map || node["data"] is! Map) {
      throw const QqApiError(
        "QQ 音乐响应缺少必要数据，请稍后重试",
        kind: QqFailure.invalidResponse,
      );
    }
    return node["data"] as Map;
  }

  QqApiError _failure(Object error, String action) {
    print("QQ 音乐$action失败：$error");
    if (error is DioException && error.response != null) {
      final status = error.response!.statusCode;
      return QqApiError(
        "QQ 音乐服务请求失败（HTTP $status），请稍后重试",
        kind: QqFailure.rejected,
        code: status,
      );
    }
    return QqApiError(
      error is DioException ? "QQ 音乐网络异常，请检查网络后重试" : "QQ 音乐响应格式变化，请稍后重试",
      kind:
          error is DioException ? QqFailure.network : QqFailure.invalidResponse,
    );
  }

  @override
  Future<List<SearchItem>> hotSongs() async => const [];

  @override
  Future<List<ChartHit>?> getChartHits(String chartKey) async => null;

  @override
  Future<SearchItem> searchDetail(String id) async =>
      throw const QqApiError("QQ 音乐暂不支持详情接口");

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  static String _randomGuid() =>
      (DateTime.now().microsecondsSinceEpoch % 100000000).toString();
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse("$value") ?? 0;
}

bool isQqPlayable(Map song) {
  bool zero(dynamic value) => value == 0 || value == "0";
  final pay = song["pay"];
  if (pay is Map) return zero(pay["pay_play"]) || zero(pay["payplay"]);
  return zero(song["payplay"]);
}

SearchItem? qqSongToSearchItem(Map song) {
  final mid = "${song["mid"] ?? ""}";
  final name = "${song["name"] ?? ""}".trim();
  if (mid.isEmpty || name.isEmpty) return null;
  final singers = song["singer"] as List? ?? const [];
  final author = singers
      .whereType<Map>()
      .map((s) => "${s["name"] ?? ""}")
      .where((s) => s.isNotEmpty)
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

List<SearchItem> parseQqSongs(List list) => [
      for (final song in list)
        if (song is Map && isQqPlayable(song))
          if (qqSongToSearchItem(song) case final SearchItem item) item,
    ];

String? parseQqVkey(Map data) => _qqVkeyUrls(data).firstOrNull;

List<String> _qqVkeyUrls(Map data) {
  final node = data["req_0"];
  final body = node is Map ? node["data"] : null;
  if (body is! Map) return const [];
  final infos = body["midurlinfo"] as List? ?? const [];
  final info = infos.firstOrNull;
  final purl = info is Map ? info["purl"] : null;
  if (purl is! String || purl.isEmpty) return const [];
  final direct = Uri.tryParse(purl);
  if (direct != null && (direct.scheme == "https" || direct.scheme == "http")) {
    return [purl];
  }
  final domains =
      (body["sip"] as List? ?? const []).whereType<String>().where((s) {
    final uri = Uri.tryParse(s);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == "https" || uri.scheme == "http");
  }).toList();
  // 保留 CDN 备链；优先普通域名，ws 前缀只作最后回退。
  final ordered = [
    ...domains.where((s) => !Uri.parse(s).host.startsWith("ws")),
    ...domains.where((s) => Uri.parse(s).host.startsWith("ws")),
  ];
  return {for (final domain in ordered) "$domain$purl"}.toList();
}

class QqSearchResponse extends SearchResponse {
  const QqSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
    super.hasMore,
  });
}
