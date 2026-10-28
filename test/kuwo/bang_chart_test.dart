import "package:bobomusic/origin_sdk/kuwo/kuwo_api.dart";
import "package:flutter_test/flutter_test.dart";

/// ksong.s 官方榜单解析纯函数（真实接口不联网，字段样本取自 2026-10 实测响应）
void main() {
  group("parseKuwoBangSongs", () {
    test("真实字段结构：rid/歌名/歌手/时长映射，复用 kuwoSongToSearchItem", () {
      const raw = {
        "name": "酷我飙升榜",
        "num": 80,
        "musiclist": [
          {
            "id": "7201115",
            "name": "我好像在哪见过你",
            "artist": "薛之谦",
            "album": "初学者",
            "albumid": "553415",
            "duration": 263,
            "formats": "MP3128|ALFLAC",
          },
          {
            // MUSIC_ 前缀的 rid 也兼容
            "id": "MUSIC_143849264",
            "name": "夜曲",
            "artist": "周杰伦",
          },
        ],
      };
      final hits = parseKuwoBangSongs(raw);
      expect(hits.length, 2);
      expect(hits[0].name, "我好像在哪见过你");
      expect(hits[0].artist, "薛之谦");
      expect(hits[0].item!.id, "kuwo:7201115");
      expect(hits[0].item!.duration, 263);
      expect(hits[1].item!.id, "kuwo:143849264");
    });

    test("无 rid/歌名的脏条目被过滤", () {
      const raw = {
        "musiclist": [
          {"name": "无名曲"},
          {"id": "123", "name": ""},
          {"id": "456", "name": "有效歌", "artist": "某人"},
        ],
      };
      final hits = parseKuwoBangSongs(raw);
      expect(hits.length, 1);
      expect(hits[0].item!.id, "kuwo:456");
    });

    test("musiclist 缺失/类型异常返回空列表", () {
      expect(parseKuwoBangSongs({}), isEmpty);
      expect(parseKuwoBangSongs({"musiclist": null}), isEmpty);
      expect(parseKuwoBangSongs({"musiclist": ["不是对象", 42]}), isEmpty);
    });
  });
}
