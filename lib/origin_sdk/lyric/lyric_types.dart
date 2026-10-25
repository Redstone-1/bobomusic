/// 歌词源（三顺位链：网易直连 → LRCLIB → timelessq 备胎）
enum LyricSource {
  netease("网易云"),
  lrclib("LRCLIB"),
  timelessq("备用源");

  final String label;
  const LyricSource(this.label);
}

/// 一条歌词搜索候选（不含歌词正文；取词时再按 source/id 请求）
class LyricCandidate {
  final LyricSource source;
  final String id;
  final String title;
  final String artist;
  final int durationSec;

  const LyricCandidate({
    required this.source,
    required this.id,
    required this.title,
    required this.artist,
    required this.durationSec,
  });

  @override
  bool operator ==(Object other) =>
      other is LyricCandidate && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);
}

/// 归一化：去空白与常见标点/括号符号，转小写（中英文标题比对用）
String normalizeLyricText(String input) => input
    .toLowerCase()
    .replaceAll(
      RegExp(r'''[\s\-_/·,，.。!！?？:：;；()（）\[\]【】《》<>"']'''),
      "",
    );

/// 自动匹配最佳候选：标题优先、歌手次之、时长兜底
/// 返回 null 表示候选为空；标题完全对不上时仍回退首个候选（搜索源本身按相关度排序）
LyricCandidate? pickBestLyricCandidate(
  List<LyricCandidate> candidates, {
  required String title,
  required String artist,
  int? durationSec,
}) {
  if (candidates.isEmpty) return null;
  final wantTitle = normalizeLyricText(title);
  final wantArtist = normalizeLyricText(artist);
  LyricCandidate? best;
  var bestScore = -1;
  for (final c in candidates) {
    final cTitle = normalizeLyricText(c.title);
    final cArtist = normalizeLyricText(c.artist);
    var score = 0;
    if (wantTitle.isNotEmpty && cTitle == wantTitle) {
      score += 100;
    } else if (wantTitle.isNotEmpty &&
        (cTitle.contains(wantTitle) || wantTitle.contains(cTitle))) {
      score += 55;
    }
    if (wantArtist.isNotEmpty && cArtist.isNotEmpty) {
      if (cArtist == wantArtist) {
        score += 30;
      } else if (cArtist.contains(wantArtist) || wantArtist.contains(cArtist)) {
        score += 18;
      }
    }
    if (durationSec != null && c.durationSec > 0) {
      final diff = (c.durationSec - durationSec).abs();
      if (diff <= 3) {
        score += 20;
      } else if (diff <= 10) {
        score += 8;
      }
    }
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return best ?? candidates.first;
}
