/// 一行歌词（时间轴已换算为毫秒；标准 LRC 两位小数是百分秒，必须 ×10）
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});
}

/// LRC 时间标签：[mm:ss]、[mm:ss.x]、[mm:ss.xx]、[mm:ss.xxx]（兼容 [mm:ss:xx]）
final _timeTag = RegExp(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]");

/// 小数位 → 毫秒：1 位=十分秒 ×100，2 位=百分秒 ×10，3 位=毫秒
int _fractionToMs(String? fraction) {
  if (fraction == null || fraction.isEmpty) return 0;
  final digits = fraction.length > 3 ? fraction.substring(0, 3) : fraction;
  final value = int.tryParse(digits) ?? 0;
  return switch (digits.length) {
    1 => value * 100,
    2 => value * 10,
    _ => value,
  };
}

/// 解析 LRC：支持一行多时间标签、元信息行跳过、实体还原、按时间排序
/// 空文本行（间奏）丢弃，避免当前行定位停在无字行
List<LyricLine> parseLrc(String raw) {
  final lines = <LyricLine>[];
  for (final rawLine in raw.split(RegExp(r"\r?\n"))) {
    final matches = _timeTag.allMatches(rawLine).toList();
    if (matches.isEmpty) continue; // [ar:]/[ti:]/[by:] 等元信息
    final text = rawLine
        .replaceAll(_timeTag, "")
        .replaceAll(RegExp(r"<[^>]*>"), "")
        .replaceAll("&apos;", "'")
        .replaceAll("&#39;", "'")
        .replaceAll("&amp;", "&")
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .trim();
    if (text.isEmpty) continue;
    for (final m in matches) {
      final minutes = int.tryParse(m.group(1)!) ?? 0;
      final seconds = int.tryParse(m.group(2)!) ?? 0;
      final ms = _fractionToMs(m.group(3));
      lines.add(
        LyricLine(
          time: Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
          text: text,
        ),
      );
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  // 同一时间戳的重复行去重（多源合并时常见）
  final deduped = <LyricLine>[];
  for (final line in lines) {
    if (deduped.isNotEmpty &&
        deduped.last.time == line.time &&
        deduped.last.text == line.text) {
      continue;
    }
    deduped.add(line);
  }
  return deduped;
}

/// 当前行下标（-1 = 还没到第一行）
/// [offsetMs] 正数表示歌词整体延后，因此查找位置 = 播放位置 - offset
int activeLyricIndex(
  List<LyricLine> lines,
  Duration position, {
  int offsetMs = 0,
}) {
  if (lines.isEmpty) return -1;
  final targetMs = position.inMilliseconds - offsetMs;
  if (targetMs < lines.first.time.inMilliseconds) return -1;
  var low = 0;
  var high = lines.length - 1;
  var result = 0;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (lines[mid].time.inMilliseconds <= targetMs) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

/// 合并翻译 LRC：同一时间戳的行追加「原文 / 翻译」（网易 tlyric、备胎 tlyric）
/// 无翻译时原样返回；返回仍是合法 LRC（保留时间标签，可持久化/再解析）
String mergeLrcTranslation(String mainLrc, String? translatedLrc) {
  if (translatedLrc == null || translatedLrc.trim().isEmpty) return mainLrc;
  final translated = {
    for (final line in parseLrc(translatedLrc))
      line.time.inMilliseconds: line.text,
  };
  if (translated.isEmpty) return mainLrc;
  final merged = [
    for (final line in parseLrc(mainLrc))
      LyricLine(
        time: line.time,
        text: translated[line.time.inMilliseconds] == null
            ? line.text
            : "${line.text} / ${translated[line.time.inMilliseconds]}",
      ),
  ];
  return [for (final line in merged) "[${_formatLrcTime(line.time)}]${line.text}"]
      .join("\n");
}

String _formatLrcTime(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, "0");
  final seconds = (d.inSeconds % 60).toString().padLeft(2, "0");
  final centis = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, "0");
  return "$minutes:$seconds.$centis";
}
