import "package:audio_service/audio_service.dart";

import "../../data/models/track.dart";
import "play_mode.dart";

/// 系统媒体会话命令（通知栏 / 耳机键 / 锁屏）
/// 由 Playback 状态机实现；handler 只做转发，不持有业务状态
abstract class SystemPlaybackCommands {
  Future<void> systemPlay();
  Future<void> systemPause();
  Future<void> systemNext();
  Future<void> systemPrevious();
  Future<void> systemSeek(Duration position);
  Future<void> systemStop();
}

/// 一次系统会话快照（避免 handler 反向依赖 Riverpod 状态类）
class SystemPlaybackSnapshot {
  final Track? track;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final PlayMode mode;
  final int queueIndex;

  const SystemPlaybackSnapshot({
    required this.track,
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.mode,
    required this.queueIndex,
  });
}

/// 全局系统媒体会话（Android 初始化；桌面/测试为 null 时全部跳过）
PlaybackAudioHandler? playbackAudioHandler;

/// 初始化 audio_service（仅 Android；需 AndroidManifest 的 AudioServiceActivity/Service）
/// 失败不阻塞 App 启动：播放/UI 仍可用，只是没有通知栏与耳机键
Future<void> initPlaybackAudioService() async {
  if (playbackAudioHandler != null) return;
  try {
    playbackAudioHandler = await AudioService.init(
      builder: PlaybackAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: "com.bobomusic.channel.playback",
        androidNotificationChannelName: "播放状态",
        androidNotificationChannelDescription: "啵啵音乐播放控制",
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    print("系统媒体会话初始化失败（桌面/测试环境可忽略）：$e");
  }
}

/// audio_service 桥接：命令转发给 Playback，状态由 Playback 单向推入
class PlaybackAudioHandler extends BaseAudioHandler {
  SystemPlaybackCommands? commands;
  String? _lastTrackId;

  @override
  Future<void> play() async => commands?.systemPlay();

  @override
  Future<void> pause() async => commands?.systemPause();

  @override
  Future<void> skipToNext() async => commands?.systemNext();

  @override
  Future<void> skipToPrevious() async => commands?.systemPrevious();

  @override
  Future<void> seek(Duration position) async => commands?.systemSeek(position);

  @override
  Future<void> stop() async => commands?.systemStop();

  /// 状态机 → 系统会话（曲目/播放态/进度/模式）
  void sync(SystemPlaybackSnapshot snap) {
    final item = buildSystemMediaItem(snap);
    if (snap.track == null) {
      _lastTrackId = null;
      mediaItem.add(null);
    } else if (item != null && _lastTrackId != snap.track!.id) {
      _lastTrackId = snap.track!.id;
      mediaItem.add(item);
    } else if (item != null &&
        item.duration != null &&
        mediaItem.value?.duration != item.duration) {
      // 真时长通常在 ready 后到达：补一次 mediaItem，通知栏进度条才正确
      mediaItem.add(item);
    }
    playbackState.add(buildSystemPlaybackState(snap));
  }

  /// 清空系统会话（播放器销毁时）
  void detach() {
    commands = null;
    _lastTrackId = null;
    mediaItem.add(null);
    playbackState.add(PlaybackState());
  }
}

/// 快照 → MediaItem（纯函数，便于单测；封面缺失时 artUri 为 null）
MediaItem? buildSystemMediaItem(SystemPlaybackSnapshot snap) {
  final track = snap.track;
  if (track == null) return null;
  final duration = snap.duration > Duration.zero
      ? snap.duration
      : (track.duration != null ? Duration(seconds: track.duration!) : null);
  final cover = track.cover;
  return MediaItem(
    id: track.id,
    title: track.name,
    artist: track.author,
    duration: duration,
    artUri: cover == null || cover.isEmpty ? null : Uri.tryParse(cover),
  );
}

/// 快照 → PlaybackState（纯函数，便于单测）
PlaybackState buildSystemPlaybackState(SystemPlaybackSnapshot snap) {
  return PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      snap.playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ],
    androidCompactActionIndices: const [0, 1, 2],
    processingState: snap.buffering
        ? AudioProcessingState.buffering
        : AudioProcessingState.ready,
    playing: snap.playing,
    updatePosition: snap.position,
    bufferedPosition: snap.position,
    speed: 1.0,
    queueIndex: snap.queueIndex >= 0 ? snap.queueIndex : null,
    systemActions: const {MediaAction.seek},
    repeatMode: switch (snap.mode) {
      PlayMode.singleLoop => AudioServiceRepeatMode.one,
      PlayMode.listLoop => AudioServiceRepeatMode.all,
      PlayMode.shuffle || PlayMode.sequential => AudioServiceRepeatMode.none,
    },
    shuffleMode: snap.mode == PlayMode.shuffle
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none,
  );
}
