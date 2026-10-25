import "dart:convert";

import "package:dio/dio.dart";

import "lrc.dart";
import "lyric_types.dart";

/// 歌词服务抽象（三顺位链）。测试注入 Fake，避免真实网络。
abstract class LyricService {
  /// 按关键词搜索候选；按网易 → LRCLIB → 备胎顺序，首个非空结果即返回
  Future<List<LyricCandidate>> search(String keyword);

  /// 取候选的 LRC 原文（失败返回 null，由调用方提示）
  Future<String?> fetch(LyricCandidate candidate);
}

/// 全局可替换实例（与 biliApi/appPrefs 同一环境单例模式；测试改指 Fake）
LyricService lyricService = DefaultLyricService();

const _userAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

class DefaultLyricService implements LyricService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: {"User-Agent": _userAgent},
    ),
  );

  @override
  Future<List<LyricCandidate>> search(String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    // 三顺位：任一源失败/无结果就落到下一个
    for (final source in const [
      LyricSource.netease,
      LyricSource.lrclib,
      LyricSource.timelessq,
    ]) {
      try {
        final list = await _searchSource(source, keyword.trim());
        if (list.isNotEmpty) return list;
      } catch (e) {
        print("歌词搜索失败（${source.label}）：$e");
      }
    }
    return const [];
  }

  @override
  Future<String?> fetch(LyricCandidate candidate) async {
    try {
      final lrc = switch (candidate.source) {
        LyricSource.netease => await _fetchNetease(candidate.id),
        LyricSource.lrclib => await _fetchLrclib(candidate),
        LyricSource.timelessq => await _fetchTimelessq(candidate.id),
      };
      return (lrc == null || lrc.trim().isEmpty) ? null : lrc;
    } catch (e) {
      print("歌词获取失败（${candidate.source.label}）：$e");
      return null;
    }
  }

  // ---- 网易（免登录直连）----

  Future<List<LyricCandidate>> _searchSource(
    LyricSource source,
    String keyword,
  ) async {
    return switch (source) {
      LyricSource.netease => _searchNetease(keyword),
      LyricSource.lrclib => _searchLrclib(keyword),
      LyricSource.timelessq => _searchTimelessq(keyword),
    };
  }

  Future<List<LyricCandidate>> _searchNetease(String keyword) async {
    final response = await _dio.get(
      "https://music.163.com/api/search/get",
      queryParameters: {
        "s": keyword,
        "type": "1",
        "limit": "10",
        "offset": "0",
      },
      options: Options(headers: {"Referer": "https://music.163.com/"}),
    );
    final data = _json(response.data);
    final songs = data["result"]?["songs"] as List? ?? const [];
    return [
      for (final song in songs)
        LyricCandidate(
          source: LyricSource.netease,
          id: "${song["id"]}",
          title: "${song["name"] ?? ""}",
          artist: (song["artists"] as List? ?? const [])
              .map((a) => "${a["name"] ?? ""}")
              .where((n) => n.isNotEmpty)
              .join(" / "),
          durationSec: ((song["duration"] as num?) ?? 0) ~/ 1000,
        ),
    ];
  }

  Future<String?> _fetchNetease(String id) async {
    final response = await _dio.get(
      "https://music.163.com/api/song/lyric",
      queryParameters: {"id": id, "lv": "1", "tv": "-1"},
      options: Options(headers: {"Referer": "https://music.163.com/"}),
    );
    final data = _json(response.data);
    final lrc = data["lrc"]?["lyric"] as String?;
    if (lrc == null) return null;
    return mergeLrcTranslation(lrc, data["tlyric"]?["lyric"] as String?);
  }

  // ---- LRCLIB（免 key FOSS）----

  Future<List<LyricCandidate>> _searchLrclib(String keyword) async {
    final response = await _dio.get(
      "https://lrclib.net/api/search",
      queryParameters: {"q": keyword},
    );
    final list = response.data is List ? response.data as List : const [];
    return [
      for (final item in list)
        if (item is Map && item["syncedLyrics"] != null)
          LyricCandidate(
            source: LyricSource.lrclib,
            id: "${item["id"]}",
            title: "${item["trackName"] ?? ""}",
            artist: "${item["artistName"] ?? ""}",
            durationSec: ((item["duration"] as num?) ?? 0).round(),
          ),
    ];
  }

  Future<String?> _fetchLrclib(LyricCandidate candidate) async {
    final response = await _dio.get(
      "https://lrclib.net/api/get",
      queryParameters: {
        "track_name": candidate.title,
        "artist_name": candidate.artist,
        if (candidate.durationSec > 0) "duration": "${candidate.durationSec}",
      },
    );
    final data = _json(response.data);
    return data["syncedLyrics"] as String?;
  }

  // ---- timelessq 备胎（腾讯代理）----

  Future<List<LyricCandidate>> _searchTimelessq(String keyword) async {
    final response = await _dio.get(
      "https://api.timelessq.com/music/tencent/search",
      queryParameters: {"keyword": keyword, "page": "1", "pageSize": "10"},
    );
    final data = _json(response.data);
    final list = data["data"]?["list"] as List? ?? const [];
    return [
      for (final song in list)
        LyricCandidate(
          source: LyricSource.timelessq,
          id: "${song["songmid"]}",
          title: "${song["songname"] ?? ""}",
          artist: (song["singer"] as List? ?? const [])
              .map((s) => "${s["name"] ?? ""}")
              .where((n) => n.isNotEmpty)
              .join(" / "),
          durationSec: (song["interval"] as num?)?.round() ?? 0,
        ),
    ];
  }

  Future<String?> _fetchTimelessq(String songmid) async {
    final response = await _dio.get(
      "https://api.timelessq.com/music/tencent/lyric",
      queryParameters: {"songmid": songmid},
    );
    final data = _json(response.data);
    final lrc = data["data"]?["lyric"] as String?;
    if (lrc == null) return null;
    return mergeLrcTranslation(lrc, data["data"]?["tlyric"] as String?);
  }

  dynamic _json(dynamic data) {
    if (data is String) return jsonDecode(data);
    return data;
  }
}
