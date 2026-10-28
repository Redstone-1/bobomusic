import "package:bobomusic/origin_sdk/qianqian/qianqian_api.dart";
import "package:flutter_test/flutter_test.dart";

/// 千千音乐解析纯函数（真实接口不联网，字段样本取自 2026-10 实测响应）
void main() {
  group("qianqianSongToSearchItem", () {
    test("完整条目：TSID 前缀/封面/歌手/秒时长", () {
      final item = qianqianSongToSearchItem({
        "id": "T10065400429",
        "title": "等晴天",
        "isVip": 0,
        "duration": 268,
        "pic": "https://img01.dmhmusic.com/0513/M00/99/8.jpg",
        "albumTitle": "等晴天",
        "artist": [
          {"artistCode": "A10267395", "name": "周深"},
        ],
      });
      expect(item!.id, "qianqian:T10065400429");
      expect(item.name, "等晴天");
      expect(item.author, "周深");
      expect(item.cover, "https://img01.dmhmusic.com/0513/M00/99/8.jpg");
      expect(item.duration, 268);
    });

    test("id 缺省回退 assetId；无 id/空标题脏数据返回 null", () {
      expect(
        qianqianSongToSearchItem({"assetId": "T9", "title": "歌"})!.id,
        "qianqian:T9",
      );
      expect(qianqianSongToSearchItem({"title": "无名"}), isNull);
      expect(qianqianSongToSearchItem({"id": "T1", "title": ""}), isNull);
    });
  });

  group("isQianqianPlayable", () {
    test("isVip=0/缺省可播，1/true 不可播", () {
      expect(isQianqianPlayable({"isVip": 0}), isTrue);
      expect(isQianqianPlayable({}), isTrue);
      expect(isQianqianPlayable({"isVip": 1}), isFalse);
      expect(isQianqianPlayable({"isVip": true}), isFalse);
    });
  });

  group("parseQianqianSongs / parseQianqianChartHits", () {
    const tracks = [
      {
        "id": "T1", "title": "免费歌", "isVip": 0, "duration": 200,
        "artist": [{"name": "甲"}], "pic": "https://c/1.jpg",
      },
      {
        "id": "T2", "title": "VIP歌", "isVip": 1, "duration": 200,
        "artist": [{"name": "乙"}],
      },
      {"title": "无 TSID"},
    ];

    test("搜索解析：只留非 VIP 条目", () {
      final items = parseQianqianSongs(tracks);
      expect(items.length, 1);
      expect(items.first.id, "qianqian:T1");
    });

    test("榜单解析：同口径过滤 + ChartHit 映射", () {
      final hits = parseQianqianChartHits(tracks);
      expect(hits.length, 1);
      expect(hits.first.name, "免费歌");
      expect(hits.first.artist, "甲");
      expect(hits.first.item!.origin.value, "qianqian");
    });
  });

  group("qianqianDurationToSec", () {
    test("秒数（接口实测口径）/字符串秒/缺省", () {
      expect(qianqianDurationToSec(268), 268);
      expect(qianqianDurationToSec("268"), 268);
      expect(qianqianDurationToSec(null), 0);
    });
  });
}
