import "package:bobomusic/origin_sdk/qq/qq_api.dart";
import "package:flutter_test/flutter_test.dart";

/// QQ 音乐解析纯函数（真实接口不联网，字段样本取自 2026-10 实测响应）
void main() {
  group("qqSongToSearchItem", () {
    test("完整条目：mid 前缀/多歌手拼接/专辑封面 URL/秒时长", () {
      final item = qqSongToSearchItem({
        "mid": "002f6kjO3yqwfd",
        "name": "晴天",
        "interval": 269,
        "singer": [
          {"id": 4558, "name": "周杰伦"},
          {"name": "群星"},
        ],
        "album": {"mid": "003PUyMm2nxGkD", "name": "叶惠美"},
      });
      expect(item!.id, "qq:002f6kjO3yqwfd");
      expect(item.name, "晴天");
      expect(item.author, "周杰伦/群星");
      expect(
        item.cover,
        "https://y.gtimg.cn/music/photo_new/T002R300x300M000003PUyMm2nxGkD.jpg",
      );
      expect(item.duration, 269);
    });

    test("无 mid/空歌名脏数据返回 null；无专辑时封面为空", () {
      expect(qqSongToSearchItem({"name": "无名"}), isNull);
      expect(qqSongToSearchItem({"mid": "m", "name": "  "}), isNull);
      final noAlbum = qqSongToSearchItem({"mid": "m", "name": "歌"});
      expect(noAlbum!.cover, "");
    });
  });

  group("isQqPlayable", () {
    test("pay.pay_play=0（新）与 payplay=0（旧）可播，其余不可播", () {
      expect(isQqPlayable({"pay": {"pay_play": 0}}), isTrue);
      expect(isQqPlayable({"payplay": 0}), isTrue);
      expect(isQqPlayable({"pay": {"pay_play": 1}}), isFalse);
      expect(isQqPlayable({}), isFalse);
    });
  });

  group("parseQqSongs", () {
    test("过滤 VIP 与脏数据", () {
      final items = parseQqSongs([
        {"mid": "free", "name": "免费歌", "interval": 200, "pay": {"pay_play": 0},
         "singer": [{"name": "甲"}]},
        {"mid": "vip", "name": "VIP歌", "interval": 200, "pay": {"pay_play": 1}},
        {"name": "无 mid"},
      ]);
      expect(items.length, 1);
      expect(items.first.id, "qq:free");
    });
  });

  group("parseQqVkey", () {
    test("purl 拼接：跳过 ws 前缀域名", () {
      final url = parseQqVkey({
        "req_0": {
          "data": {
            "midurlinfo": [
              {"purl": "M800abc.mp3?vkey=xyz"},
            ],
            "sip": ["http://ws.stream.example/", "http://aqqmusic.tc.qq.com/"],
          },
        },
      });
      expect(url, "http://aqqmusic.tc.qq.com/M800abc.mp3?vkey=xyz");
    });

    test("purl 为空（VIP/受限）返回 null；空 ws 域名列表回退首项", () {
      expect(
        parseQqVkey({
          "req_0": {"data": {"midurlinfo": [{"purl": ""}], "sip": []}},
        }),
        isNull,
      );
      expect(
        parseQqVkey({
          "req_0": {"data": {"midurlinfo": [{"purl": "a.mp3"}], "sip": ["http://ws.x/"]}},
        }),
        "http://ws.x/a.mp3",
      );
    });
  });
}
