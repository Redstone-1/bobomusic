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

    test("旧接口字段残留 JS 转义：\\u0026 解为 &（歌手名实测泄漏点）", () {
      const raw =
          "{'abslist':[{'MUSICRID':'MUSIC_1','SONGNAME':'歌名','ARTIST':'A2O LITE\\\\u0026A2O','DURATION':'200'}]}";
      final data = parseKuwoJson(raw) as Map;
      final item = kuwoSongToSearchItem(
        (data["abslist"] as List).first as Map,
      );
      expect(item!.author, "A2O LITE&A2O");
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

  group("parseKuwoRankHtml", () {
    test("官方榜单 SSR：可见歌名/歌手 + musicList 的 rid/封面/时长", () {
      const html = '''
        <p class="song_name" data-v>夜曲</p><p class="artist" data-v>周杰伦</p>
        <p class="song_name" data-v>七里香</p><p class="artist" data-v>周杰伦</p>
        "bang/index/bangList":[{leader:"酷我热歌榜",musicList:[
          {musicrid:"MUSIC_143849264",artist:"周杰伦",pic120:"https:\\\\u002F\\\\u002Fimg.example\\\\u002Fa.jpg",duration:227,payInfo:{x:"y"}},
          {musicrid:456,artist:"周杰伦",pic120:"https:\\\\u002F\\\\u002Fimg.example\\\\u002Fb.jpg",duration:240}
        ]}]
      ''';
      final items = parseKuwoRankHtml(html);
      expect(items, hasLength(2));
      expect(items[0].id, "kuwo:143849264");
      expect(items[0].name, "夜曲");
      expect(items[0].author, "周杰伦");
      expect(items[0].cover, "https://img.example/a.jpg");
      expect(items[0].duration, 227);
      expect(items[1].id, "kuwo:456");
      expect(items[1].name, "七里香");
    });

    test("没有榜单数据返回空列表", () {
      expect(parseKuwoRankHtml("<html>no rank</html>"), isEmpty);
    });

    test("可见榜单标题：歌名/歌手成对解析", () {
      const html = '''
        <p class="song_name" data-v>山风山风等等我</p>
        <p class="artist" data-v>万海东</p>
        <p class="song_name" data-v>人生路漫漫</p>
        <p class="artist" data-v>白小白</p>
      ''';
      final titles = parseKuwoRankTitles(html);
      expect(titles, hasLength(2));
      expect(titles[0].name, "山风山风等等我");
      expect(titles[0].artist, "万海东");
    });

    test("SSR 可见文本残留 JS 转义：歌手 \\u0026 解为 &", () {
      const html = '''
        <p class="song_name" data-v>合作曲</p>
        <p class="artist" data-v>歌手甲\\u0026歌手乙</p>
      ''';
      final titles = parseKuwoRankTitles(html);
      expect(titles.single.artist, "歌手甲&歌手乙");
    });

    test("双重转义 \\\\\\u0026 解为 &，不残留反斜杠（真机实测形态）", () {
      // 数据源存在 \\u0026（两道反斜杠）的过度转义，单解一层会残留 \
      const html = '''
        <p class="song_name" data-v>合作曲二</p>
        <p class="artist" data-v>歌手甲\\\\u0026歌手乙</p>
      ''';
      final titles = parseKuwoRankTitles(html);
      expect(titles.single.artist, "歌手甲&歌手乙");
      expect(titles.single.artist, isNot(contains("\\")));
    });

    test("搜索结果匹配：拒绝错歌手，接受同歌手版本", () {
      const title = KuwoRankTitle(name: "山风山风等等我", artist: "万海东");
      final wrong = _hotItem("1", "山风山风等等我", "别的歌手");
      final right = _hotItem("2", "山风山风等等我 (DJ沈念版)", "万海东");
      expect(pickKuwoRankItem([wrong, right], title)?.id, "kuwo:2");
      expect(pickKuwoRankItem([wrong], title), isNull);
    });
  });
}

SearchItem _hotItem(String id, String name, String artist) => SearchItem(
      id: "kuwo:$id",
      cover: "",
      name: name,
      duration: 200,
      author: artist,
      origin: OriginType.kuwo,
      isSeasonDisplay: false,
      type: SearchType.music,
    );
