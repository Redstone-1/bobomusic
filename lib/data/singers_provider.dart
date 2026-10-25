import "dart:convert";

import "package:flutter/services.dart" show rootBundle;
import "package:riverpod_annotation/riverpod_annotation.dart";

import "models/track.dart";

part "singers_provider.g.dart";

/// 热门歌手条目（assets/chinese.json，旧版广场同源；S3 按所有者决定仅迁移此项）
class SingerEntry {
  final String id;
  final String name;
  final String desc;
  final List<Track> tracks;

  const SingerEntry({
    required this.id,
    required this.name,
    required this.desc,
    required this.tracks,
  });

  factory SingerEntry.fromJson(Map<String, dynamic> json) => SingerEntry(
        id: json["id"] as String,
        name: json["name"] as String,
        desc: (json["desc"] ?? "") as String,
        tracks: [
          for (final m in (json["musicList"] as List? ?? []))
            Track(
              id: m["id"] as String,
              name: m["name"] as String,
              author: (m["author"] ?? "") as String,
              cover: m["cover"] as String?,
              duration: m["duration"] as int?,
              origin: OriginType.values.firstWhere(
                (o) => o.name == (m["origin"] ?? "bili"),
                orElse: () => OriginType.bili,
              ),
            ),
        ],
      );
}

/// 热门歌手列表（打包资源，随 App 内置；失败由页面三态呈现）
/// 可替换：测试注入 mock 列表（asset 真实 I/O 在 FakeAsync 下不会完成）
List<SingerEntry>? hotSingersTestOverride;

@Riverpod(keepAlive: true)
Future<List<SingerEntry>> hotSingers(Ref ref) async {
  if (hotSingersTestOverride != null) return hotSingersTestOverride!;
  final raw = await rootBundle.loadString("assets/chinese.json");
  final list = jsonDecode(raw) as List;
  return [for (final e in list) SingerEntry.fromJson(e as Map<String, dynamic>)];
}
