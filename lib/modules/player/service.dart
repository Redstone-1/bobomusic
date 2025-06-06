import "dart:async";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/player/instance.dart";
import "package:just_audio/just_audio.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";

class AudioPlayerHandler extends BaseAudioHandler {
  final BBPlayer player = BBPlayer();
  late PlaybackEvent _audioEvent;
  // 移除手动维护的 _playing 变量，直接使用播放器状态

  double get _speed => player.audio.speed;
  MusicItem? get current => player.current;

  set current(MusicItem? value) {
    player.current = value;
    _updateMediaItem();
  }

  AudioPlayerHandler() {
    player.audio.playbackEventStream.listen((event) {
      _audioEvent = event;
    });
    player.audio.playerStateStream.listen((state) {
      _updateMediaItem();
      _broadcastState(); // 直接更新状态，无需延迟
    });
    _updateMediaItem();
    player.audio.positionStream.listen((position) {
      _updatePosition();
    });
    player.audio.durationStream.listen((duration) {
      if (mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    print("🎮 收到自定义操作: $name, 参数: $extras");

    switch (name) {
      case "toggle_lyrics":
        // 切换歌词显示状态
        print("🎮 收到自定义操作: toggle_lyrics}");
        break;
    }

    return super.customAction(name, extras);
  }

  @override
  Future<void> play({MusicItem? music}) async {
    if (music != null) {
      await player.play(music: music); // 处理传入新音乐的情况
    } else {
      if (player.current == null) return; // 无当前音乐时返回
      await player.audio.play(); // 继续播放当前音乐
    }
    _updatePosition();
  }

  @override
  Future<void> pause() async {
    await player.audio.pause(); // 直接调用播放器暂停
    _updatePosition();
  }

  @override
  Future<void> seek(Duration position) => player.audio.seek(position);

  @override
  Future<void> skipToPrevious() async {
    await player.prev();
    _updateMediaItem();
  }

  @override
  Future<void> skipToNext() async {
    await player.next();
    _updateMediaItem();
  }

  void _updateMediaItem() {
    if (player.current != null) {
      final newItem = music2mediaItem(player.current!);
      mediaItem.add(newItem.copyWith(
        duration: player.audio.duration ?? newItem.duration,
      ));
    }
  }

  void _updatePosition() {
    _audioEvent = _audioEvent.copyWith(
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      updateTime: DateTime.now(),
    );
  }

  void _broadcastState() {
    eventBus.fire(ScrollLyric());

    final controls = [
      const MediaControl(
        action: MediaAction.skipToPrevious,
        androidIcon: "drawable/skip_previous",
        label: "上一曲",
      ),
      MediaControl(
        action: MediaAction.playPause,
        androidIcon: player.audio.playing ? "drawable/pause_circle" : "drawable/play_circle",
        label: "暂停/播放",
      ),
      const MediaControl(
        action: MediaAction.skipToNext,
        androidIcon: "drawable/skip_next",
        label: "下一曲",
      ),
    ];

    final processingState = {
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[player.audio.processingState] ?? AudioProcessingState.ready;

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: processingState,
      playing: player.audio.playing, // 直接使用播放器状态
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      speed: _speed,
      queueIndex: _audioEvent.currentIndex,
    ));
  }
}

MediaItem music2mediaItem(MusicItem music) {
  return MediaItem(
    id: music.id,
    title: music.name,
    album: music.author,
    artist: music.author,
    duration: Duration(seconds: music.duration),
  );
}