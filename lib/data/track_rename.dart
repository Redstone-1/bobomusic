import "models/track.dart";

enum TrackRenameRule { leadingDigits, specialChars, removeChars }

class TrackRenameSuggestion {
  const TrackRenameSuggestion(
      {required this.track,
      required this.name,
      required this.author,
      required this.confident,
      required this.reason});
  final Track track;
  final String name;
  final String author;
  final bool confident;
  final String reason;
  bool get changed =>
      name != track.effectiveName || author != track.effectiveAuthor;
}

// 开头数字后紧贴的分隔符号一并清掉；中间数字（如 24K Magic）不在此规则职责内，
// 是否清除由用户自行选择规则决定。
final _leadingDigits = RegExp(r"^[0-9０-９]+[\s.、,，:：;；)）(—_·-]*");
// 特殊字符 = 字母/数字/空白之外的一切（半全角标点、符号、emoji 等）。
final _specialChars = RegExp(r"[^\p{L}\p{N}\s]", unicode: true);
final _whitespace = RegExp(r"\s+");

/// 只提出格式整理建议，不纠正歌名、不访问网络，也不写入数据库。
/// 预览是规则与输入的纯函数，规则切换或输入变化时由页面实时重算。
List<TrackRenameSuggestion> suggestTrackRenames(
  List<Track> tracks, {
  TrackRenameRule rule = TrackRenameRule.leadingDigits,
  String removeChars = "",
}) {
  return [
    for (final track in tracks)
      (() {
        final original = track.effectiveName.trim();
        var name = original;
        switch (rule) {
          case TrackRenameRule.leadingDigits:
            name = original.replaceFirst(_leadingDigits, "").trim();
          case TrackRenameRule.specialChars:
            name = original
                .replaceAll(_specialChars, "")
                .replaceAll(_whitespace, " ")
                .trim();
          case TrackRenameRule.removeChars:
            // 整串匹配：输入什么删什么完整子串，全部出现位置都删。
            if (removeChars.isNotEmpty) {
              name = original.replaceAll(removeChars, "").trim();
            }
        }
        var confident = false;
        var reason = "未命中，可手动编辑建议";
        if (name != original && name.isNotEmpty) {
          confident = true;
          reason = switch (rule) {
            TrackRenameRule.leadingDigits => "已清除开头数字",
            TrackRenameRule.specialChars => "已清除特殊字符",
            TrackRenameRule.removeChars => "删除指定字符",
          };
        }
        // 整理后歌名为空（如纯编号行）时拒绝建议，保留原名。
        if (name.isEmpty) {
          name = original;
          confident = false;
          reason = "整理后歌名为空，已跳过";
        }
        return TrackRenameSuggestion(
            track: track,
            name: name,
            author: track.effectiveAuthor,
            confident: confident,
            reason: reason);
      })()
  ];
}
