import "package:bobomusic/origin_sdk/netease/netease_api.dart";
import "package:flutter_test/flutter_test.dart";

/// 网易云解析纯函数（真实接口不联网，字段样本取自 2026-10 实测响应）
void main() {
  group("neteaseSongToSearchItem", () {
    test("完整条目（v3 playlist 形态 ar/al）：id 前缀/封面/歌手/毫秒转秒", () {
      final item = neteaseSongToSearchItem({
        "id": 2668397359,
        "name": "晴天",
        "fee": 8,
        "duration": 269000,
        "ar": [
          {"id": 6452, "name": "RyaVocal"},
        ],
        "al": {"id": 123, "name": "专辑", "picUrl": "https://p1.music.126.net/x.jpg"},
      });
      expect(item, isNotNull);
      expect(item!.id, "netease:2668397359");
      expect(item.name, "晴天");
      expect(item.author, "RyaVocal");
      expect(item.cover, "https://p1.music.126.net/x.jpg");
      expect(item.duration, 269);
    });

    test("老接口形态（artists/album）同样兼容", () {
      final item = neteaseSongToSearchItem({
        "id": 1,
        "name": "老形态歌",
        "fee": 0,
        "artists": [
          {"name": "老歌手"},
        ],
        "album": {"picUrl": "https://p1.music.126.net/old.jpg"},
      });
      expect(item!.author, "老歌手");
      expect(item.cover, "https://p1.music.126.net/old.jpg");
    });

    test("无 id/非数字 id/空歌名的脏数据返回 null", () {
      expect(neteaseSongToSearchItem({"name": "无名"}), isNull);
      expect(neteaseSongToSearchItem({"id": "abc", "name": "歌"}), isNull);
      expect(neteaseSongToSearchItem({"id": 1, "name": "  "}), isNull);
    });

    test("缺省字段（无歌手/专辑/时长）不抛错", () {
      final item = neteaseSongToSearchItem({"id": 5, "name": "歌"});
      expect(item!.id, "netease:5");
      expect(item.author, "");
      expect(item.cover, "");
      expect(item.duration, 0);
    });
  });

  group("isNeteasePlayable", () {
    test("fee 0/8 可播，其余（VIP=1、购专=4、缺失）不可播", () {
      expect(isNeteasePlayable({"fee": 0}), isTrue);
      expect(isNeteasePlayable({"fee": 8}), isTrue);
      expect(isNeteasePlayable({"fee": 1}), isFalse);
      expect(isNeteasePlayable({"fee": 4}), isFalse);
      expect(isNeteasePlayable({}), isFalse);
    });
  });

  group("parseNeteaseSongs / parseNeteaseChartHits", () {
    const songs = [
      {
        "id": 1, "name": "免费歌", "fee": 8, "duration": 200000,
        "artists": [{"name": "甲"}], "album": {"picUrl": "https://c/1.jpg"},
      },
      {
        "id": 2, "name": "VIP歌", "fee": 1, "duration": 200000,
        "artists": [{"name": "乙"}], "album": {"picUrl": "https://c/2.jpg"},
      },
      {"id": 3, "name": "无 fee 脏数据", "duration": 1},
    ];

    test("搜索解析：只留免费可播条目", () {
      final items = parseNeteaseSongs(songs);
      expect(items.length, 1);
      expect(items.first.id, "netease:1");
    });

    test("榜单解析：同口径过滤 + ChartHit 映射", () {
      final hits = parseNeteaseChartHits(songs);
      expect(hits.length, 1);
      expect(hits.first.name, "免费歌");
      expect(hits.first.artist, "甲");
      expect(hits.first.item!.origin.value, "netease");
    });
  });

  group("neteaseDurationToSec", () {
    test("毫秒数/字符串毫秒 → 秒（向下取整）", () {
      expect(neteaseDurationToSec(269000), 269);
      expect(neteaseDurationToSec("269999"), 269);
      expect(neteaseDurationToSec(null), 0);
    });
  });
}
