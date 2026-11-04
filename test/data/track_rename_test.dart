import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/track_rename.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  Track song(String id, String name, {String author = "合集上传者"}) =>
      Track(id: id, name: name, author: author);

  test("整批编号和重复歌手可识别，保留原文不纠错", () {
    final result = suggestTrackRenames([
      song("a", "001 周杰伦 东方破"),
      song("b", "002 周杰伦 发如雪"),
    ]);
    expect(result.map((s) => s.name), ["东方破", "发如雪"]);
    expect(result.map((s) => s.author), ["周杰伦", "周杰伦"]);
    expect(result.every((s) => s.confident && s.changed), isTrue);
  });

  test("混合歌单只整理匹配的补零编号组，正常数字歌名保留", () {
    final result = suggestTrackRenames([
      song("a", "001 周杰伦 东方破"),
      song("b", "002 周杰伦 发如雪"),
      song("c", "8 Mile", author: "Eminem"),
      song("d", "9 Crimes", author: "Damien Rice"),
    ]);
    expect(result.take(2).every((s) => s.changed && s.confident), isTrue);
    expect(result.skip(2).map((s) => s.name), ["8 Mile", "9 Crimes"]);
    expect(result.skip(2).every((s) => !s.changed && !s.confident), isTrue);
  });

  test("无补零编号只认可从 1 开始的连续段，不扩展到其他数字段", () {
    final result = suggestTrackRenames([
      song("a", "1 周杰伦 晴天"),
      song("b", "2 周杰伦 夜曲"),
      song("c", "8 Mile"),
      song("d", "9 Crimes"),
    ]);
    expect(result.map((s) => s.name), ["晴天", "夜曲", "8 Mile", "9 Crimes"]);
    expect(result.skip(2).every((s) => !s.confident), isTrue);
  });

  test("不同补零宽度、分隔格式及断开的孤立编号不共用识别证据", () {
    final result = suggestTrackRenames([
      song("a", "001 周杰伦 晴天"),
      song("b", "002 周杰伦 夜曲"),
      song("c", "03 周杰伦 稻香"),
      song("d", "004.周杰伦 花海"),
      song("e", "009 周杰伦 七里香"),
    ]);
    expect(result.take(2).map((s) => s.name), ["晴天", "夜曲"]);
    expect(result.skip(2).every((s) => !s.confident && !s.changed), isTrue);
  });

  test("明确选择仅去除序号时仍可处理单首，不受智能分组限制", () {
    final result = suggestTrackRenames([song("a", "009. 七里香")],
            rule: TrackRenameRule.number)
        .single;
    expect(result.name, "七里香");
    expect(result.confident, isTrue);
  });

  test("仅去序号支持紧贴中文的补零编号，智能模式不自动猜测", () {
    final tracks = [
      song("a", "01周杰伦-晴天"),
      song("b", "02周杰伦-手写的从前"),
      song("c", "24K Magic"),
      song("d", "1984年")
    ];
    final explicit = suggestTrackRenames(tracks, rule: TrackRenameRule.number);
    expect(explicit.map((s) => s.name),
        ["周杰伦-晴天", "周杰伦-手写的从前", "24K Magic", "1984年"]);
    expect(explicit.take(2).every((s) => s.changed && s.confident), isTrue);
    expect(suggestTrackRenames(tracks).every((s) => !s.changed), isTrue);
  });

  test("年份和歌名内数字保留，孤立编号默认不猜测", () {
    final result = suggestTrackRenames([
      song("a", "2002"),
      song("b", "1984 世界"),
      song("c", "24K Magic"),
      song("d", "001 某首歌"),
      song("e", "说好不哭"),
    ]);
    expect(result.every((s) => !s.changed && !s.confident), isTrue);
  });

  test("空格及同名前缀本身不当成歌手", () {
    final result = suggestTrackRenames([
      song("a", "Love Story"),
      song("b", "Love Again"),
    ]);
    expect(result.every((s) => !s.changed), isTrue);
  });

  test("歌曲本身的开头数字和英文共同词不冒充序号或歌手", () {
    final names =
        suggestTrackRenames([song("a", "8 Mile"), song("b", "9 Crimes")]);
    expect(names.every((s) => !s.changed), isTrue);
    final numbered = suggestTrackRenames([
      song("a", "001 Love Story"),
      song("b", "002 Love Again"),
    ]);
    expect(numbered.map((s) => s.name), ["Love Story", "Love Again"]);
    expect(numbered.every((s) => s.author == "合集上传者"), isTrue);
  });

  test("分隔符顺序不明确时等待确认，指定顺序后可拆分", () {
    final tracks = [song("a", "歌曲 - 歌手")];
    expect(suggestTrackRenames(tracks).single.confident, isFalse);
    final explicit = suggestTrackRenames(tracks,
            rule: TrackRenameRule.separator, artistFirst: false)
        .single;
    expect(explicit.name, "歌曲");
    expect(explicit.author, "歌手");
    expect(explicit.confident, isTrue);
  });

  test("已知歌手或整批重复歌手可以确定分隔符顺序", () {
    final result = suggestTrackRenames([
      song("a", "周杰伦 - 晴天"),
      song("b", "周杰伦 - 夜曲"),
      song("c", "稻香 - 周杰伦", author: "周杰伦"),
    ]);
    expect(result.map((s) => s.name), ["晴天", "夜曲", "稻香"]);
    expect(result.every((s) => s.confident), isTrue);
  });

  test("移除整个名称得到空歌名时拒绝建议", () {
    final result = suggestTrackRenames([song("a", "固定前缀")],
            rule: TrackRenameRule.prefix, prefix: "固定前缀")
        .single;
    expect(result.name, "固定前缀");
    expect(result.confident, isFalse);
  });

  test("手动编辑标记供预览默认跳过，封面编辑不算改名", () {
    final result = suggestTrackRenames(const [
      Track(id: "a", name: "001 晴天", author: "", displayName: "001 我的晴天"),
      Track(id: "b", name: "002 夜曲", author: "", displayCover: "封面"),
    ]);
    expect(result.first.manuallyEdited, isTrue);
    expect(result.last.manuallyEdited, isFalse);
  });
}
