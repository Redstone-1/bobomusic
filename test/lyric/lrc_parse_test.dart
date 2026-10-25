import "package:bobomusic/origin_sdk/lyric/lrc.dart";
import "package:bobomusic/origin_sdk/lyric/lyric_types.dart";
import "package:flutter_test/flutter_test.dart";

/// S4.4 歌词解析/定位纯函数测试（百分秒 ×10 是旧版 10 倍慢的根因）
void main() {
  group("parseLrc", () {
    test("两位小数按百分秒换算（1.50s 不是 1.05s/1.5ms）", () {
      final lines = parseLrc("[00:01.50]第一行\n[00:02.05]第二行");
      expect(lines.length, 2);
      expect(lines[0].time, const Duration(milliseconds: 1500));
      expect(lines[1].time, const Duration(milliseconds: 2050));
    });

    test("一位/三位小数兼容", () {
      final lines = parseLrc("[00:01.5]甲\n[00:02.345]乙");
      expect(lines[0].time, const Duration(milliseconds: 1500));
      expect(lines[1].time, const Duration(milliseconds: 2345));
    });

    test("一行多时间标签：同一句歌词生成多行", () {
      final lines = parseLrc("[00:10.00][00:20.00]副歌");
      expect(lines.map((e) => e.text), ["副歌", "副歌"]);
      expect(lines[0].time, const Duration(seconds: 10));
      expect(lines[1].time, const Duration(seconds: 20));
    });

    test("元信息行/空文本行跳过，实体还原，按时间排序", () {
      final lines = parseLrc(
        "[ar:歌手]\n[00:05.00]后来\n[00:01.00]先来 &amp; 早\n[00:03.00]",
      );
      expect(lines.map((e) => e.text), ["先来 & 早", "后来"]);
      expect(lines[0].time, const Duration(seconds: 1));
    });

    test("翻译合并：同时间戳追加「原文 / 翻译」，仍是可解析 LRC", () {
      final merged = mergeLrcTranslation(
        "[00:01.00]Hello\n[00:03.50]World",
        "[00:01.00]你好",
      );
      final lines = parseLrc(merged);
      expect(lines[0].text, "Hello / 你好");
      expect(lines[1].text, "World");
      // 无翻译时原样返回
      expect(mergeLrcTranslation("[00:01.00]Hi", null), "[00:01.00]Hi");
    });
  });

  group("activeLyricIndex", () {
    final lines = parseLrc("[00:01.00]一\n[00:03.00]二\n[00:05.00]三");

    test("首行前返回 -1，区间内取最后一条已到时间的行", () {
      expect(activeLyricIndex(lines, const Duration(milliseconds: 500)), -1);
      expect(activeLyricIndex(lines, const Duration(seconds: 2)), 0);
      expect(activeLyricIndex(lines, const Duration(seconds: 3)), 1);
      expect(activeLyricIndex(lines, const Duration(seconds: 30)), 2);
    });

    test("校准偏移：正数歌词延后（查找位置提前）", () {
      // 播放 4s，歌词延后 2s → 按 2s 定位到第一行
      expect(
        activeLyricIndex(
          lines,
          const Duration(seconds: 4),
          offsetMs: 2000,
        ),
        0,
      );
      // 歌词提前 2s → 按 6s 定位到第三行
      expect(
        activeLyricIndex(
          lines,
          const Duration(seconds: 4),
          offsetMs: -2000,
        ),
        2,
      );
    });
  });

  group("pickBestLyricCandidate", () {
    const candidates = [
      LyricCandidate(
        source: LyricSource.netease,
        id: "1",
        title: "夜曲",
        artist: "周杰伦",
        durationSec: 227,
      ),
      LyricCandidate(
        source: LyricSource.lrclib,
        id: "2",
        title: "夜曲 (Live)",
        artist: "周杰伦",
        durationSec: 260,
      ),
      LyricCandidate(
        source: LyricSource.timelessq,
        id: "3",
        title: "完全无关",
        artist: "别人",
        durationSec: 100,
      ),
    ];

    test("标题完全匹配 + 歌手 + 时长优先", () {
      final best = pickBestLyricCandidate(
        candidates,
        title: "夜曲",
        artist: "周杰伦",
        durationSec: 228,
      );
      expect(best?.id, "1");
    });

    test("标题包含匹配也能选中（无完全匹配时）", () {
      final best = pickBestLyricCandidate(
        candidates,
        title: "夜曲 (Live)",
        artist: "周杰伦",
        durationSec: 260,
      );
      expect(best?.id, "2");
    });

    test("空候选返回 null", () {
      expect(
        pickBestLyricCandidate(const [], title: "夜曲", artist: "周杰伦"),
        isNull,
      );
    });
  });
}
