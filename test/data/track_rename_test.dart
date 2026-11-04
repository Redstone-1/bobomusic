import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/track_rename.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  Track song(String id, String name, {String author = "合集上传者"}) =>
      Track(id: id, name: name, author: author);

  test("清除开头数字去掉编号与紧贴分隔符号，默认规则即命中", () {
    final result = suggestTrackRenames([
      song("a", "001. 夜曲-"),
      song("b", "01周杰伦-晴天"),
      song("c", "普通歌名"),
    ]);
    expect(result[0].name, "夜曲-");
    expect(result[0].confident && result[0].changed, isTrue);
    expect(result[1].name, "周杰伦-晴天");
    expect(result[1].confident && result[1].changed, isTrue);
    expect(result[2].name, "普通歌名");
    expect(result[2].confident || result[2].changed, isFalse);
  });

  test("清除开头数字只动开头，中间数字与无符号编号按规则清除", () {
    final result = suggestTrackRenames([
      song("a", "24K Magic"),
      song("b", "1984年"),
    ], rule: TrackRenameRule.leadingDigits);
    // 规则行为可预期：开头数字是歌名一部分时同样清除，由用户自行选择是否使用
    expect(result[0].name, "K Magic");
    expect(result[1].name, "年");
    expect(result.every((s) => s.confident && s.changed), isTrue);
  });

  test("清除特殊字符保留中英文数字空格，连续空白并入一个", () {
    final result = suggestTrackRenames([
      song("a", "夜曲-·（Live）版！"),
      song("b", "Why  So Sad? 7 Rings"),
    ], rule: TrackRenameRule.specialChars);
    expect(result[0].name, "夜曲Live版");
    expect(result[1].name, "Why So Sad 7 Rings");
    expect(result.every((s) => s.confident && s.changed), isTrue);
  });

  test("删除指定字符按整串匹配，全部出现位置都删除", () {
    final result = suggestTrackRenames(
        [song("a", "001. 夜曲"), song("b", "夜曲 (001.) 现场版")],
        rule: TrackRenameRule.removeChars,
        removeChars: "001.");
    expect(result[0].name, "夜曲");
    expect(result[1].name, "夜曲 () 现场版");
    expect(result.every((s) => s.confident && s.changed), isTrue);
  });

  test("删除指定字符未命中或删空时保持原样", () {
    final result = suggestTrackRenames(
        [song("a", "夜曲"), song("b", "固定字符")],
        rule: TrackRenameRule.removeChars,
        removeChars: "固定字符");
    // 未命中：保持原样不提建议；整串命中删空：拒绝建议
    expect(result.map((s) => s.name), ["夜曲", "固定字符"]);
    expect(result.every((s) => !s.confident && !s.changed), isTrue);
  });

  test("整理后歌名为空时拒绝建议，保留原名", () {
    final result = suggestTrackRenames([song("a", "001")],
        rule: TrackRenameRule.leadingDigits).single;
    expect(result.name, "001");
    expect(result.confident, isFalse);
    expect(result.changed, isFalse);
  });
}
