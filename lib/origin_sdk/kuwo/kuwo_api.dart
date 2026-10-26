import "dart:convert";

import "package:dio/dio.dart";

import "../origin_types.dart";

/// 酷我接口错误（类型化，UI 决定提示；不依赖 B 站错误类型）
class KuwoApiError implements Exception {
  final String message;
  const KuwoApiError(this.message);

  @override
  String toString() => message;
}

/// 酷我第二音源（D11）：免签名搜索 + anti.s 取流
/// 搜索优先新接口，失败/空结果回退 web_2013 老接口（两套响应结构都兼容）
class KuwoApi implements OriginService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://www.kuwo.cn/",
      },
    ),
  );

  @override
  Future<SearchResponse> search(SearchParams params) async {
    final keyword = params.keyword.trim();
    if (keyword.isEmpty) {
      return KuwoSearchResponse(
        current: params.page,
        total: 0,
        pageSize: params.pageSize ?? 20,
        data: const [],
      );
    }
    final size = params.pageSize ?? 20;
    // 新接口
    try {
      final response = await _dio.get(
        "https://www.kuwo.cn/api/v1/search/music",
        queryParameters: {
          "key": keyword,
          "pn": "${params.page}",
          "rn": "$size",
        },
      );
      final data = _json(response.data);
      final list = data["data"]?["list"] as List? ?? const [];
      final items = _mapSongs(list);
      if (items.isNotEmpty) {
        final total = _asInt(data["data"]?["total"]);
        return KuwoSearchResponse(
          current: params.page,
          total: total > 0 ? total : items.length,
          pageSize: size,
          data: items,
        );
      }
    } catch (e) {
      print("酷我新接口搜索失败，尝试旧接口：$e");
    }
    // 老接口（web_2013，免签名）
    try {
      final response = await _dio.get(
        "https://search.kuwo.cn/r.s",
        queryParameters: {
          "all": keyword,
          "ft": "music",
          "itemset": "web_2013",
          "client": "kt",
          "pn": "${params.page - 1}",
          "rn": "$size",
          "rformat": "json",
          "encoding": "utf8",
        },
      );
      final data = _json(response.data);
      final list = data["abslist"] as List? ?? const [];
      final items = _mapSongs(list);
      final total = _asInt(data["TOTAL"]);
      return KuwoSearchResponse(
        current: params.page,
        total: total > 0 ? total : items.length,
        pageSize: size,
        data: items,
      );
    } catch (e) {
      throw KuwoApiError("酷我搜索失败：$e");
    }
  }

  @override
  Future<SearchItem> searchDetail(String id) async {
    // 酷我条目即单曲，无多 P/合集详情；搜索页不会调用
    throw const KuwoApiError("酷我暂不支持详情接口");
  }

  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    final rid = id.startsWith("kuwo:") ? id.substring("kuwo:".length) : id;
    if (rid.isEmpty) throw const KuwoApiError("酷我歌曲 ID 不正确");
    try {
      final response = await _dio.get(
        "https://antiserver.kuwo.cn/anti.s",
        queryParameters: {
          "type": "convert_url3",
          "rid": rid,
          "format": "mp3",
          "response": "url",
        },
      );
      final url = parseKuwoUrl(response.data);
      if (url == null || url.isEmpty) {
        throw const KuwoApiError("酷我未返回可用播放地址");
      }
      return MusicUrl(
        url: url,
        headers: {"Referer": "https://www.kuwo.cn/"},
      );
    } on KuwoApiError {
      rethrow;
    } catch (e) {
      throw KuwoApiError("酷我取流失败：$e");
    }
  }

  List<SearchItem> _mapSongs(List list) {
    final items = <SearchItem>[];
    for (final song in list) {
      if (song is Map) {
        final item = kuwoSongToSearchItem(song);
        if (item != null) items.add(item);
      }
    }
    return items;
  }

  dynamic _json(dynamic data) => parseKuwoJson(data);
}

/// 酷我搜索单条 → 统一 SearchItem（新/旧接口字段兼容；纯函数便于测试）
/// 无有效 rid/歌名的脏数据返回 null，由调用方过滤
SearchItem? kuwoSongToSearchItem(Map song) {
  final rawRid =
      "${song["rid"] ?? song["musicrid"] ?? song["MUSICRID"] ?? song["id"] ?? ""}";
  final rid = rawRid.replaceFirst(RegExp(r"^MUSIC_"), "");
  final name = decodeKuwoText(
    "${song["name"] ?? song["songName"] ?? song["SONGNAME"] ?? ""}",
  );
  if (rid.isEmpty || name.isEmpty) return null;
  final artist = decodeKuwoText(
    "${song["artist"] ?? song["artistName"] ?? song["ARTIST"] ?? ""}",
  );
  final rawCover =
      "${song["pic"] ?? song["albumpic"] ?? song["web_albumpic_short"] ?? song["cover"] ?? ""}";
  return SearchItem(
    id: "kuwo:$rid",
    cover: kuwoCoverUrl(rawCover),
    name: name,
    duration: parseKuwoDuration(
      song["duration"] ?? song["DURATION"] ?? song["songTimeMinutes"],
    ),
    author: artist,
    origin: OriginType.kuwo,
    isSeasonDisplay: false,
    type: SearchType.music,
  );
}

/// 旧接口文本清洗：HTML 实体、标签、首尾空白
String decodeKuwoText(String value) => value
    .replaceAll("&nbsp;", " ")
    .replaceAll("&amp;", "&")
    .replaceAll("&apos;", "'")
    .replaceAll("&#39;", "'")
    .replaceAll(RegExp(r"<[^>]*>"), "")
    .trim();

/// 旧接口封面是相对路径（120/11/8/xxx.jpg），补全 Kuwo 图床前缀
String kuwoCoverUrl(String raw) {
  final cover = raw.trim();
  if (cover.isEmpty) return "";
  if (cover.startsWith("http://") || cover.startsWith("https://")) return cover;
  return "https://img4.kuwo.cn/star/albumcover/$cover";
}

/// 酷我时长统一成秒（新接口 int 秒 / 旧接口 DURATION 秒 / mm:ss 字符串）
int parseKuwoDuration(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.round();
  final text = "$raw".trim();
  if (text.isEmpty) return 0;
  if (text.contains(":")) {
    final parts = text.split(":");
    if (parts.length >= 2) {
      final min = int.tryParse(parts[0]) ?? 0;
      final sec = int.tryParse(parts[1]) ?? 0;
      return min * 60 + sec;
    }
  }
  return int.tryParse(text) ?? 0;
}

/// 解析 anti.s 响应：纯 URL / JSON 文本 / {url} / {data:{url}}
String? parseKuwoUrl(dynamic data) {
  if (data == null) return null;
  if (data is Map) {
    final direct = data["url"];
    if (direct is String && _looksLikeUrl(direct)) return direct;
    final nested = data["data"];
    if (nested is String && _looksLikeUrl(nested)) return nested;
    if (nested is Map) return parseKuwoUrl(nested);
    return null;
  }
  if (data is String) {
    final text = data.trim();
    if (_looksLikeUrl(text)) return text;
    try {
      return parseKuwoUrl(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }
  return null;
}

bool _looksLikeUrl(String value) =>
    value.startsWith("http://") || value.startsWith("https://");

/// 酷我旧接口返回“单引号 JSON”（{'abslist':[...]}），先按标准 JSON 解析，
/// 失败再把单引号分隔符转成双引号；并裁掉前后缀非 JSON 文本
dynamic parseKuwoJson(dynamic data) {
  if (data is! String) return data;
  var text = data.trim();
  final start = text.indexOf("{");
  if (start > 0) text = text.substring(start);
  final end = text.lastIndexOf("}");
  if (end >= 0 && end + 1 < text.length) text = text.substring(0, end + 1);
  try {
    return jsonDecode(text);
  } catch (_) {
    return jsonDecode(_singleQuoteToDouble(text));
  }
}

/// 单引号 JSON → 双引号 JSON（字符串内部的双引号转义；保留转义单引号）
String _singleQuoteToDouble(String input) {
  final out = StringBuffer();
  var inString = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inString) {
      if (ch == r"\" && i + 1 < input.length) {
        final next = input[i + 1];
        if (next == "'") {
          out.write("'");
          i++;
          continue;
        }
        out.write(ch);
        continue;
      }
      if (ch == "'") {
        out.write('"');
        inString = false;
        continue;
      }
      if (ch == '"') {
        out.write(r'\"');
        continue;
      }
      out.write(ch);
    } else {
      if (ch == "'") {
        out.write('"');
        inString = true;
        continue;
      }
      out.write(ch);
    }
  }
  return out.toString();
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse("$value") ?? 0;
}

/// 搜索响应（OriginService 只要求 SearchResponse 抽象，提供具体实现）
class KuwoSearchResponse extends SearchResponse {
  const KuwoSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
  });
}
