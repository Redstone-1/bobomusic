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
  Future<List<SearchItem>> hotSongs() async {
    // 官方榜单页是 SSR 数据（不需要 CSRF）；页面可见标题作为真实热榜来源
    String html = "";
    try {
      final response = await _dio.get<String>(
        "https://www.kuwo.cn/rankList/16",
        options: Options(responseType: ResponseType.plain),
      );
      html = response.data?.toString() ?? "";
      final items = parseKuwoRankHtml(html);
      if (items.isNotEmpty) return items.take(10).toList();
    } catch (e) {
      print("酷我热歌榜页面获取失败：$e");
    }

    // SSR 的 musicList 可能被风控裁剪；用可见标题/歌手走旧搜索解析 rid
    final titles = parseKuwoRankTitles(html);
    if (titles.isNotEmpty) {
      final resolved = <SearchItem>[];
      for (final title in titles.take(8)) {
        try {
          final items = await _searchLegacy(title.name, size: 10);
          final best = pickKuwoRankItem(items, title);
          if (best != null) resolved.add(best);
        } catch (e) {
          print("酷我热歌标题解析失败 [${title.name}]：$e");
        }
        if (resolved.length >= 10) break;
      }
      if (resolved.isNotEmpty) return resolved;
    }

    // 最后兜底：旧搜索「热门歌曲」
    try {
      return await _searchLegacy("热门歌曲", size: 10);
    } catch (e) {
      print("酷我热门歌曲兜底失败：$e");
      return const [];
    }
  }

  /// 旧接口搜索（web_2013，免签名）：解析榜单标题时避免重复试新接口
  Future<List<SearchItem>> _searchLegacy(
    String keyword, {
    int size = 10,
  }) async {
    final response = await _dio.get(
      "https://search.kuwo.cn/r.s",
      queryParameters: {
        "all": keyword,
        "ft": "music",
        "itemset": "web_2013",
        "client": "kt",
        "pn": "0",
        "rn": "$size",
        "rformat": "json",
        "encoding": "utf8",
      },
    );
    final data = _json(response.data);
    final list = data["abslist"] as List? ?? const [];
    return _mapSongs(list);
  }

  /// 官方热歌榜（唯一可用的 SSR 真榜；/rankList/{其它id} 服务端忽略 id，
  /// www bang API 被风控——实测结论，勿再按候选 id 猜测）
  Future<KuwoChart> hotChart() async {
    final hits = await hotHits();
    return KuwoChart(key: "hot", name: "热歌榜", hits: hits);
  }

  /// 官方榜单页可见标题：SSR 被裁剪时仍可展示真实热榜，点播时再解析 rid
  Future<List<KuwoHotHit>> hotHits() async {
    String html = "";
    try {
      final response = await _dio.get<String>(
        "https://www.kuwo.cn/rankList/16",
        options: Options(responseType: ResponseType.plain),
      );
      html = response.data?.toString() ?? "";
      final titles = parseKuwoRankTitles(html);
      final direct = parseKuwoRankHtml(html);
      if (titles.isNotEmpty) {
        return [
          for (var i = 0; i < titles.length; i++)
            KuwoHotHit(
              name: titles[i].name,
              artist: titles[i].artist,
              item: i < direct.length ? direct[i] : null,
            ),
        ];
      }
      if (direct.isNotEmpty) {
        return [
          for (final item in direct)
            KuwoHotHit(
              name: item.name,
              artist: item.author,
              item: item,
            ),
        ];
      }
    } catch (e) {
      print("酷我热榜页面获取失败：$e");
    }

    // 页面完全不可用时才回退旧搜索，避免整页空白
    try {
      final items = await _searchLegacy("热门歌曲", size: 10);
      return [
        for (final item in items)
          KuwoHotHit(name: item.name, artist: item.author, item: item),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 主题歌单卡（legacy search 按关键词取歌）：搜索结果非官方榜单，
  /// 卡片名称如实为主题关键词（经典老歌/网络热歌等），不冒充官方榜
  Future<KuwoChart> themeChart(String keyword) async {
    final items = await _searchLegacy(keyword, size: 30);
    return KuwoChart(
      key: "theme:$keyword",
      name: keyword,
      hits: [
        for (final item in items)
          KuwoHotHit(name: item.name, artist: item.author, item: item),
      ],
    );
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
        contentType: "audio/mpeg",
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

/// 解析酷我官方榜单页（/rankList/16）的热歌：
/// SSR 的 musicList 给 rid/封面/时长，页面可见的 song_name/artist 给歌名歌手；
/// Nuxt 会把部分字符串压成变量，因此优先用可见文本，缺失才用对象里的字面量。
List<SearchItem> parseKuwoRankHtml(String html) {
  if (html.trim().isEmpty) return const [];
  final names = _visibleHtmlTexts(html, "song_name");
  final artists = _visibleHtmlTexts(html, "artist");
  final array = _firstRankMusicList(html);
  if (array == null) return const [];

  final items = <SearchItem>[];
  for (final object in _topLevelObjects(array)) {
    final rid = _intField(object, "musicrid") ?? _intField(object, "rid");
    if (rid == null || rid <= 0) continue;
    final index = items.length;
    final visibleName =
        index < names.length ? names[index] : "";
    final visibleArtist =
        index < artists.length ? artists[index] : "";
    final name = visibleName.isNotEmpty
        ? visibleName
        : (_stringField(object, "name") ?? "");
    final author = visibleArtist.isNotEmpty
        ? visibleArtist
        : (_stringField(object, "artist") ?? "");
    if (name.trim().isEmpty) continue;
    final pic =
        _stringField(object, "pic120") ?? _stringField(object, "pic") ?? "";
    items.add(
      SearchItem(
        id: "kuwo:$rid",
        cover: kuwoCoverUrl(_unescapeJsString(pic)),
        name: decodeKuwoText(name),
        duration: _intField(object, "duration") ?? 0,
        author: decodeKuwoText(author),
        origin: OriginType.kuwo,
        isSeasonDisplay: false,
        type: SearchType.music,
      ),
    );
    if (items.length >= 10) break;
  }
  return items;
}

/// 页面可见的 `<p class="song_name">` / `<p class="artist">` 文本
List<String> _visibleHtmlTexts(String html, String className) {
  final pattern = RegExp(
    'class="${RegExp.escape(className)}"[^>]*>([^<]*)</p>',
  );
  return [
    for (final match in pattern.allMatches(html))
      decodeKuwoText(match.group(1) ?? ""),
  ];
}

/// 官方榜单页可见歌名/歌手（SSR musicList 被裁剪时用于旧搜索解析 rid）
List<KuwoRankTitle> parseKuwoRankTitles(String html) {
  if (html.trim().isEmpty) return const [];
  final names = _visibleHtmlTexts(html, "song_name");
  final artists = _visibleHtmlTexts(html, "artist");
  final count = names.length < artists.length ? names.length : artists.length;
  return [
    for (var i = 0; i < count && i < 10; i++)
      if (names[i].trim().isNotEmpty)
        KuwoRankTitle(name: names[i], artist: artists[i]),
  ];
}

class KuwoRankTitle {
  final String name;
  final String artist;

  const KuwoRankTitle({required this.name, required this.artist});
}

/// 从搜索结果选与榜单标题/歌手匹配的条目；宁可跳过，不展示错歌
SearchItem? pickKuwoRankItem(List<SearchItem> items, KuwoRankTitle title) {
  final titleKey = _rankKey(title.name);
  final artistKey = _rankKey(title.artist);
  if (titleKey.isEmpty) return null;

  SearchItem? best;
  var bestScore = -1;
  for (final item in items) {
    final itemKey = _rankKey(item.name);
    final itemArtist = _rankKey(item.author);
    final artistMatch = artistKey.isEmpty
        ? true
        : itemArtist.contains(artistKey) || artistKey.contains(itemArtist);
    if (!artistMatch) continue;
    var score = artistKey.isEmpty ? 0 : 4;
    if (itemKey == titleKey) {
      score += 6;
    } else if (itemKey.contains(titleKey) || titleKey.contains(itemKey)) {
      score += 2;
    } else {
      continue;
    }
    if (score > bestScore) {
      best = item;
      bestScore = score;
    }
  }
  return best;
}

/// 匹配键：去空白、括号版本说明、常见标点，大小写不敏感
String _rankKey(String value) => value
    .replaceAll(RegExp(r"[（(].*?[）)]"), "")
    .replaceAll(RegExp(r"\s+"), "")
    .replaceAll(RegExp(r"[，,。.!！?？·\-_/]"), "")
    .toLowerCase();

/// 在 `"bang/index/bangList"` 后取第一个非空 musicList 数组内容
String? _firstRankMusicList(String html) {
  final marker = html.indexOf('"bang/index/bangList"');
  if (marker < 0) return null;
  var searchFrom = marker;
  while (true) {
    final index = html.indexOf("musicList:[", searchFrom);
    if (index < 0) return null;
    final start = index + "musicList:[".length;
    final array = _takeArray(html, start);
    if (array != null && array.trim().isNotEmpty) return array;
    searchFrom = index + 1;
  }
}

/// 从 `[` 后开始截取到匹配的 `]`（正确处理字符串里的括号）
String? _takeArray(String text, int start) {
  var depth = 1;
  var inString = false;
  var escaped = false;
  String? quote;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r"\") {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      inString = true;
      quote = ch;
    } else if (ch == "[") {
      depth++;
    } else if (ch == "]") {
      depth--;
      if (depth == 0) return text.substring(start, i);
    }
  }
  return null;
}

/// 数组内顶层对象（跳过 payInfo 等嵌套对象）
List<String> _topLevelObjects(String array) {
  final result = <String>[];
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaped = false;
  String? quote;
  for (var i = 0; i < array.length; i++) {
    final ch = array[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r"\") {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      inString = true;
      quote = ch;
    } else if (ch == "{") {
      if (depth == 0) start = i;
      depth++;
    } else if (ch == "}") {
      depth--;
      if (depth == 0 && start >= 0) {
        result.add(array.substring(start, i + 1));
        start = -1;
      }
    }
  }
  return result;
}

String? _stringField(String object, String key) {
  final pattern = RegExp(
    '(?:^|[,{])${RegExp.escape(key)}\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
  );
  final match = pattern.firstMatch(object);
  return match == null ? null : _unescapeJsString(match.group(1) ?? "");
}

int? _intField(String object, String key) {
  final pattern = RegExp(
    '(?:^|[,{])${RegExp.escape(key)}\\s*:\\s*"?\\s*(?:MUSIC_)?(\\d+)',
  );
  final match = pattern.firstMatch(object);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// SSR 的 URL 常写成 `https:\u002F\u002F...`
String _unescapeJsString(String value) => value
    .replaceAll(r"\u002F", "/")
    .replaceAll(r"\/", "/")
    .replaceAll(r"\u0026", "&")
    .replaceAll(r"\u003D", "=")
    .replaceAll(r"\u003A", ":");

/// 搜索响应（OriginService 只要求 SearchResponse 抽象，提供具体实现）
class KuwoSearchResponse extends SearchResponse {
  const KuwoSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
  });
}
