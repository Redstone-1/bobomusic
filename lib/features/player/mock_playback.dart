import "dart:async";

import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../data/mock/mock_data.dart";
import "../../data/models/track.dart";

part "mock_playback.g.dart";

/// mock 播放状态（S1.4 批次 3 驱动 UI；S4 换真播放引擎时整文件替换，UI 侧 provider 不动）
class MockPlaybackState {
  final Track? track;
  final bool playing;

  /// 0..1（mock 快进节奏，不代表真实秒数）
  final double progress;

  /// 播放模式：0 单曲循环 / 1 列表循环 / 2 随机 / 3 顺序（S4 接 NextStrategy）
  final int modeIndex;

  const MockPlaybackState({
    this.track,
    this.playing = false,
    this.progress = 0,
    this.modeIndex = 1,
  });

  MockPlaybackState copyWith({
    Track? track,
    bool? playing,
    double? progress,
    int? modeIndex,
  }) =>
      MockPlaybackState(
        track: track ?? this.track,
        playing: playing ?? this.playing,
        progress: progress ?? this.progress,
        modeIndex: modeIndex ?? this.modeIndex,
      );
}

@riverpod
class MockPlayback extends _$MockPlayback {
  Timer? _ticker;
  int _index = -1;

  @override
  MockPlaybackState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const MockPlaybackState();
  }

  void play(Track track) {
    _index = mockTracks.indexOf(track);
    state = MockPlaybackState(track: track, playing: true);
    _ensureTicker();
  }

  void toggle() {
    if (state.track == null) return;
    state = state.copyWith(playing: !state.playing);
  }

  void seek(double fraction) =>
      state = state.copyWith(progress: fraction.clamp(0.0, 1.0));

  /// 循环切换播放模式（UI toast 文案由调用方按索引取）
  void cycleMode() =>
      state = state.copyWith(modeIndex: (state.modeIndex + 1) % 4);

  void next() => _jump(1);

  void previous() => _jump(-1);

  void _jump(int delta) {
    _index = (_index + delta + mockTracks.length) % mockTracks.length;
    state = MockPlaybackState(
      track: mockTracks[_index],
      playing: state.playing,
      progress: 0,
    );
  }

  // mock 快进：120ms 一步，约 30s 走完一首（原型同款节奏）；播完自动切下一首
  void _ensureTicker() {
    _ticker ??=
        Timer.periodic(const Duration(milliseconds: 120), (_) => _tick());
  }

  void _tick() {
    if (!state.playing) return;
    final next = state.progress + 0.004;
    if (next >= 1) {
      _jump(1);
    } else {
      state = state.copyWith(progress: next);
    }
  }
}
