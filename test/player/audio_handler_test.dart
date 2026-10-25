import "package:audio_service/audio_service.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/play_mode.dart";
import "package:bobomusic/features/player/playback_audio_handler.dart";
import "package:flutter_test/flutter_test.dart";

/// S4-A3：系统媒体会话快照映射（纯函数，不依赖 Android 平台通道）
void main() {
  const track = Track(
    id: "bili:1_BV1_2",
    name: "夜航西飞",
    author: "陈鸿宇",
    duration: 252,
    cover: "https://example.com/cover.jpg",
  );

  SystemPlaybackSnapshot snap({
    bool playing = true,
    bool buffering = false,
    PlayMode mode = PlayMode.listLoop,
    Duration duration = const Duration(seconds: 252),
    int queueIndex = 2,
  }) =>
      SystemPlaybackSnapshot(
        track: track,
        playing: playing,
        buffering: buffering,
        position: const Duration(seconds: 30),
        duration: duration,
        mode: mode,
        queueIndex: queueIndex,
      );

  test("MediaItem：曲目/歌手/时长/封面映射", () {
    final item = buildSystemMediaItem(snap())!;
    expect(item.id, track.id);
    expect(item.title, "夜航西飞");
    expect(item.artist, "陈鸿宇");
    expect(item.duration, const Duration(seconds: 252));
    expect(item.artUri.toString(), "https://example.com/cover.jpg");
  });

  test("MediaItem：无曲目返回 null；时长未就绪回退元数据", () {
    expect(
      buildSystemMediaItem(
        const SystemPlaybackSnapshot(
          track: null,
          playing: false,
          buffering: false,
          position: Duration.zero,
          duration: Duration.zero,
          mode: PlayMode.listLoop,
          queueIndex: -1,
        ),
      ),
      isNull,
    );
    final item = buildSystemMediaItem(snap(duration: Duration.zero))!;
    expect(item.duration, const Duration(seconds: 252));
  });

  test("PlaybackState：播放/暂停控制与 compact 索引", () {
    final playingState = buildSystemPlaybackState(snap());
    expect(playingState.playing, isTrue);
    expect(playingState.controls.map((c) => c.action), [
      MediaAction.skipToPrevious,
      MediaAction.pause,
      MediaAction.skipToNext,
    ]);
    expect(playingState.androidCompactActionIndices, [0, 1, 2]);
    expect(playingState.systemActions, contains(MediaAction.seek));
    expect(playingState.queueIndex, 2);

    final paused = buildSystemPlaybackState(snap(playing: false));
    expect(paused.playing, isFalse);
    expect(paused.controls[1].action, MediaAction.play);
  });

  test("PlaybackState：四模式 → repeat/shuffle 映射", () {
    expect(
      buildSystemPlaybackState(snap(mode: PlayMode.singleLoop)).repeatMode,
      AudioServiceRepeatMode.one,
    );
    expect(
      buildSystemPlaybackState(snap(mode: PlayMode.listLoop)).repeatMode,
      AudioServiceRepeatMode.all,
    );
    expect(
      buildSystemPlaybackState(snap(mode: PlayMode.sequential)).repeatMode,
      AudioServiceRepeatMode.none,
    );
    final shuffle = buildSystemPlaybackState(snap(mode: PlayMode.shuffle));
    expect(shuffle.shuffleMode, AudioServiceShuffleMode.all);
    expect(shuffle.repeatMode, AudioServiceRepeatMode.none);
  });

  test("PlaybackState：缓冲态与无队列下标", () {
    final state = buildSystemPlaybackState(
      snap(buffering: true, queueIndex: -1),
    );
    expect(state.processingState, AudioProcessingState.buffering);
    expect(state.queueIndex, isNull);
    expect(state.updatePosition, const Duration(seconds: 30));
  });
}
