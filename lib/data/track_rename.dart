import "models/track.dart";

enum TrackRenameRule { smart, number, prefix, separator }

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
  bool get manuallyEdited =>
      track.displayName != null || track.displayAuthor != null;
}

// 年份、24K 等歌名数字不能当序号；智能模式还需整批存在连续编号证据。
final _numberPrefix =
    RegExp(r"^(0\d{1,5}|[1-9]\d{0,2})([.、)）_\-]\s*|\s+)(.+)$");
final _spacedSeparator = RegExp(r"\s+[-–—|]\s+");
// 仅在用户明确选择去序号时处理「01周杰伦-晴天」；智能模式仍保留分组证据要求。
final _compactNumberPrefix = RegExp(r"^(0\d{1,5})(?=[\u4e00-\u9fff])(.+)$");

/// 编号证据只作用于相同补零宽度、分隔方式的连续段，不能推广到整个歌单。
Set<String> _consistentNumberedTracks(Map<String, RegExpMatch> numbered) {
  final groups =
      <({bool padded, int width, String separator}), Map<int, List<String>>>{};
  for (final entry in numbered.entries) {
    final digits = entry.value.group(1)!;
    final padded = digits.startsWith("0");
    final format = (
      padded: padded,
      width: padded ? digits.length : 0,
      separator: entry.value.group(2)!.trim()
    );
    final group = groups.putIfAbsent(format, () => {});
    group.putIfAbsent(int.parse(digits), () => []).add(entry.key);
  }
  final accepted = <String>{};
  for (final entry in groups.entries) {
    final numbers = entry.value.keys.toList()..sort();
    final run = <int>[];
    void acceptRun() {
      // 无补零的数字需从 1 开始，避免把 8 Mile、9 Crimes 当成独立编号段。
      if (run.length >= 2 && (entry.key.padded || run.first == 1)) {
        for (final number in run) {
          accepted.addAll(entry.value[number]!);
        }
      }
    }

    for (final number in numbers) {
      if (run.isNotEmpty && number != run.last + 1) {
        acceptRun();
        run.clear();
      }
      run.add(number);
    }
    acceptRun();
  }
  return accepted;
}

/// 只提出格式整理建议，不纠正歌名、不访问网络，也不写入数据库。
List<TrackRenameSuggestion> suggestTrackRenames(
  List<Track> tracks, {
  TrackRenameRule rule = TrackRenameRule.smart,
  String prefix = "",
  String separator = " - ",
  bool artistFirst = true,
}) {
  final numbered = <String, RegExpMatch>{};
  for (final track in tracks) {
    final match = _numberPrefix.firstMatch(track.effectiveName.trim());
    if (match != null) numbered[track.id] = match;
  }
  final regularIds = _consistentNumberedTracks(numbered);
  final cleaned = <String, String>{
    for (final track in tracks)
      track.id: regularIds.contains(track.id)
          ? numbered[track.id]!.group(3)!.trim()
          : track.effectiveName.trim(),
  };
  final firstTokens = <String, int>{};
  final lefts = <String, int>{};
  final rights = <String, int>{};
  for (final track in tracks) {
    final name = cleaned[track.id]!;
    final tokens = RegExp(r"^(\S+)\s+(.+)$").firstMatch(name);
    if (tokens != null) {
      firstTokens.update(tokens.group(1)!, (v) => v + 1, ifAbsent: () => 1);
    }
    final parts = name.split(_spacedSeparator);
    if (parts.length == 2) {
      lefts.update(parts[0].trim(), (v) => v + 1, ifAbsent: () => 1);
      rights.update(parts[1].trim(), (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return [
    for (final track in tracks)
      (() {
        final original = track.effectiveName;
        var name = original;
        var author = track.effectiveAuthor;
        var confident = false;
        var reason = "未识别到明确格式，可手动编辑建议";
        switch (rule) {
          case TrackRenameRule.number:
            final match = numbered[track.id];
            if (match != null) {
              name = match.group(3)!.trim();
              confident = true;
              reason = "去除开头序号";
            } else {
              final compact = _compactNumberPrefix.firstMatch(original.trim());
              if (compact != null) {
                name = compact.group(2)!.trim();
                confident = true;
                reason = "去除开头补零序号";
              }
            }
          case TrackRenameRule.prefix:
            if (prefix.isNotEmpty && original.startsWith(prefix)) {
              name = original.substring(prefix.length).trim();
              confident = name.isNotEmpty;
              reason = "移除指定前缀";
            }
          case TrackRenameRule.separator:
            final parts =
                separator.isEmpty ? <String>[] : original.split(separator);
            if (parts.length == 2 && parts.every((p) => p.trim().isNotEmpty)) {
              name = parts[artistFirst ? 1 : 0].trim();
              author = parts[artistFirst ? 0 : 1].trim();
              confident = true;
              reason = "按指定分隔符拆分";
            } else {
              reason = "分隔符不匹配或有多处分隔，需确认";
            }
          case TrackRenameRule.smart:
            name = cleaned[track.id]!;
            final stripped = name != original.trim();
            confident = stripped;
            reason = stripped ? "识别到连续序号，歌手保持原值" : reason;
            final parts = name.split(_spacedSeparator);
            if (parts.length == 2 && parts.every((p) => p.trim().isNotEmpty)) {
              final left = parts[0].trim();
              final right = parts[1].trim();
              final knownLeft = author.isNotEmpty && author == left;
              final knownRight = author.isNotEmpty && author == right;
              if (knownLeft ||
                  ((lefts[left] ?? 0) >= 2 && (rights[right] ?? 0) < 2)) {
                name = right;
                author = left;
                confident = true;
                reason = "识别到歌手在前的格式";
              } else if (knownRight ||
                  ((rights[right] ?? 0) >= 2 && (lefts[left] ?? 0) < 2)) {
                name = left;
                author = right;
                confident = true;
                reason = "识别到歌名在前的格式";
              } else {
                confident = false;
                reason = "无法确定歌手与歌名顺序，需确认";
              }
            } else {
              final tokens = RegExp(r"^(\S+)\s+(.+)$").firstMatch(name);
              if (tokens != null) {
                final first = tokens.group(1)!;
                // 重复首词本身不等于歌手，必须同时有编号格式或已知歌手证据。
                if ((author.isNotEmpty && first == author) ||
                    (stripped &&
                        RegExp(r"^[\u4e00-\u9fff]{2,8}$").hasMatch(first) &&
                        (firstTokens[first] ?? 0) >= 2)) {
                  name = tokens.group(2)!.trim();
                  author = first;
                  confident = true;
                  reason = "识别到序号、重复歌手与歌名";
                }
              }
            }
        }
        if (name.trim().isEmpty) {
          name = original;
          confident = false;
          reason = "整理后歌名为空，已跳过";
        }
        return TrackRenameSuggestion(
            track: track,
            name: name,
            author: author,
            confident: confident,
            reason: reason);
      })()
  ];
}
