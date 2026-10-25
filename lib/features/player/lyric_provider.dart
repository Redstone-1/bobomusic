import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/lyric/lrc.dart";
import "../../origin_sdk/lyric/lyric_service.dart";
import "../../origin_sdk/lyric/lyric_types.dart";

part "lyric_provider.g.dart";

/// 歌词视图状态：当前曲 + 原文/解析行 + 校准偏移 + 搜索候选
class LyricState {
  final String? trackId;
  final String raw;
  final List<LyricLine> lines;
  final int offsetMs;
  final bool loading;
  final bool searching;
  final String? error;
  final List<LyricCandidate> candidates;

  const LyricState({
    this.trackId,
    this.raw = "",
    this.lines = const [],
    this.offsetMs = 0,
    this.loading = false,
    this.searching = false,
    this.error,
    this.candidates = const [],
  });

  LyricState copyWith({
    String? trackId,
    String? raw,
    List<LyricLine>? lines,
    int? offsetMs,
    bool? loading,
    bool? searching,
    String? error,
    bool clearError = false,
    List<LyricCandidate>? candidates,
  }) =>
      LyricState(
        trackId: trackId ?? this.trackId,
        raw: raw ?? this.raw,
        lines: lines ?? this.lines,
        offsetMs: offsetMs ?? this.offsetMs,
        loading: loading ?? this.loading,
        searching: searching ?? this.searching,
        error: clearError ? null : error ?? this.error,
        candidates: candidates ?? this.candidates,
      );
}

/// 歌词控制器（keepAlive）：自动匹配 / 手动搜索替换 / 校准 / 删除
/// 歌词属于曲目（tracks.lyric），写库后所有歌单共享（§3.4-7）
@Riverpod(keepAlive: true)
class LyricController extends _$LyricController {
  /// 自动匹配只尝试一次/曲（失败后不反复请求网络，用户可手动搜索）
  final Set<String> _autoTried = {};

  @override
  LyricState build() => const LyricState();

  /// 曲目切换时调用：先读库；无歌词则自动匹配（网易→LRCLIB→备胎）
  Future<void> loadFor(Track track) async {
    if (state.trackId == track.id) return;
    final stored = await TrackRepository().getById(track.id);
    if (!ref.mounted) return;
    final raw = stored?.lyric ?? track.lyric ?? "";
    final offset = stored?.lyricOffsetMs ?? track.lyricOffsetMs;
    if (raw.trim().isNotEmpty) {
      state = LyricState(
        trackId: track.id,
        raw: raw,
        lines: parseLrc(raw),
        offsetMs: offset,
      );
      return;
    }
    state = LyricState(trackId: track.id, offsetMs: offset, loading: true);
    if (_autoTried.contains(track.id)) {
      state = state.copyWith(loading: false);
      return;
    }
    _autoTried.add(track.id);
    final found = await _autoMatch(track);
    if (!ref.mounted || state.trackId != track.id) return;
    if (found == null || found.trim().isEmpty) {
      state = state.copyWith(
        loading: false,
        error: "暂未匹配到歌词",
      );
      return;
    }
    await TrackRepository().updateLyric(track.id, found);
    if (!ref.mounted || state.trackId != track.id) return;
    state = LyricState(
      trackId: track.id,
      raw: found,
      lines: parseLrc(found),
      offsetMs: 0,
    );
  }

  Future<String?> _autoMatch(Track track) async {
    final candidates = await lyricService.search(
      "${track.name} ${track.author}".trim(),
    );
    if (!ref.mounted) return null;
    final best = pickBestLyricCandidate(
      candidates,
      title: track.name,
      artist: track.author,
      durationSec: track.duration,
    );
    if (best == null) return null;
    return lyricService.fetch(best);
  }

  /// 手动搜索候选（写入 state.candidates）
  Future<void> searchCandidates(Track track, String keyword) async {
    state = state.copyWith(
      searching: true,
      clearError: true,
      candidates: const [],
    );
    final list = await lyricService.search(keyword);
    if (!ref.mounted) return;
    state = state.copyWith(
      searching: false,
      candidates: list,
      error: list.isEmpty ? "没有找到歌词" : null,
    );
  }

  /// 取候选歌词（预览用，不写库）
  Future<String?> fetchCandidate(LyricCandidate candidate) =>
      lyricService.fetch(candidate);

  /// 应用歌词（写库并重置校准偏移）
  Future<void> applyLyric(Track track, String raw) async {
    await TrackRepository().updateLyric(track.id, raw);
    if (!ref.mounted) return;
    state = LyricState(
      trackId: track.id,
      raw: raw,
      lines: parseLrc(raw),
      offsetMs: 0,
    );
  }

  /// 删除歌词（写空串；库内保留行，便于后续重新匹配）
  Future<void> removeLyric(Track track) async {
    await TrackRepository().updateLyric(track.id, "");
    if (!ref.mounted) return;
    state = LyricState(trackId: track.id);
  }

  /// 校准偏移（正 = 歌词延后显示），限制 ±30s 防误触
  Future<void> adjustOffset(Track track, int deltaMs) async {
    final next = (state.offsetMs + deltaMs).clamp(-30000, 30000);
    await TrackRepository().updateLyricOffset(track.id, next);
    if (!ref.mounted) return;
    state = state.copyWith(offsetMs: next);
  }

  Future<void> resetOffset(Track track) async {
    await TrackRepository().updateLyricOffset(track.id, 0);
    if (!ref.mounted) return;
    state = state.copyWith(offsetMs: 0);
  }
}
