import "package:bobomusic/origin_sdk/kuwo/kuwo_api.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter_test/flutter_test.dart";

/// S5 酷我源解析纯函数（真实接口不联网，锁定字段兼容与 URL 形态）
void main() {
  group("parseKuwoUrl", () {
    test("纯 URL", () {
      expect(
        parseKuwoUrl("https://kuwo.example/a.mp3"),
        "https://kuwo.example/a.mp3",
      );
    });

    test("JSON 文本 / 嵌套 data", () {
      expect(
        parseKuwoUrl('{"url":"https://kuwo.example/b.mp3"}'),
        "https://kuwo.example/b.mp3",
      );
      expect(
        parseKuwoUrl('{"data":{"url":"http://kuwo.example/c.mp3"}}'),
        "http://kuwo.example/c.mp3",
      );
      expect(
        parseKuwoUrl({"data": "https://kuwo.example/d.mp3"}),
        "https://kuwo.example/d.mp3",
      );
    });

    test("空/非法返回 null", () {
      expect(parseKuwoUrl(null), isNull);
      expect(parseKuwoUrl(""), isNull);
      expect(parseKuwoUrl("not json"), isNull);
      expect(parseKuwoUrl({"code": 200}), isNull);
    });
  });

  group("parseKuwoDuration", () {
    test("数值秒 / 数字字符串 / mm:ss", () {
      expect(parseKuwoDuration(227), 227);
      expect(parseKuwoDuration("227"), 227);
      expect(parseKuwoDuration("03:47"), 227);
      expect(parseKuwoDuration(null), 0);
    });
  });

  group("kuwoSongToSearchItem", () {
    test("旧接口单引号 JSON：解析 + 实体/封面/时长映射", () {
      const raw =
          "{'TOTAL':'3511','abslist':[{'MUSICRID':'MUSIC_143849264','SONGNAME':'夜曲&nbsp;(mp3.2)','ARTIST':'周杰伦','DURATION':'227','web_albumpic_short':'120/11/8/a.jpg'}]}";
      final data = parseKuwoJson(raw) as Map;
      expect(data["TOTAL"], "3511");
      final item = kuwoSongToSearchItem(
        (data["abslist"] as List).first as Map,
      );
      expect(item, isNotNull);
      expect(item!.id, "kuwo:143849264");
      expect(item.name, "夜曲 (mp3.2)");
      expect(item.author, "周杰伦");
      expect(item.duration, 227);
      expect(item.cover, "https://img4.kuwo.cn/star/albumcover/120/11/8/a.jpg");
      expect(item.origin, OriginType.kuwo);
    });

    test("标准 JSON 不受影响（新接口 200 / 非法提示也能解析）", () {
      final data = parseKuwoJson('{"success":false,"message":"illegal"}');
      expect(data["success"], isFalse);
      expect(parseKuwoUrl({"url": "https://x/a.mp3"}), "https://x/a.mp3");
    });

    test("新接口字段：id 前缀 + origin + 时长/封面", () {
      final item = kuwoSongToSearchItem({
        "rid": 123,
        "name": "夜曲",
        "artist": "周杰伦",
        "duration": 227,
        "pic": "https://img.example/1.jpg",
      });
      expect(item, isNotNull);
      expect(item!.id, "kuwo:123");
      expect(item.name, "夜曲");
      expect(item.author, "周杰伦");
      expect(item.duration, 227);
      expect(item.cover, "https://img.example/1.jpg");
      expect(item.origin, OriginType.kuwo);
      expect(item.type, SearchType.music);
    });

    test("旧接口 MUSIC_ 前缀与 mm:ss 时长", () {
      final item = kuwoSongToSearchItem({
        "MUSICRID": "MUSIC_456",
        "SONGNAME": "漠河舞厅",
        "ARTIST": "柳爽",
        "DURATION": "03:47",
      });
      expect(item?.id, "kuwo:456");
      expect(item?.duration, 227);
    });

    test("缺 rid/歌名的脏数据返回 null", () {
      expect(kuwoSongToSearchItem({"name": "无 id"}), isNull);
      expect(kuwoSongToSearchItem({"rid": "1"}), isNull);
    });
  });

  test("SDK OriginType 已扩展 kuwo，且按 value 桥接", () {
    expect(OriginType.getByValue("kuwo"), OriginType.kuwo);
  });
}
