import "dart:async";

import "package:just_audio/just_audio.dart";

import "audio_engine.dart";
import "range_proxy_source.dart";

/// 将 just_audio 的播放生命周期 Future 转成“命令已发出”；后续错误走事件流。
class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player;
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<Object> _errorSubscription;
  Object? _lastError;
  int _playGeneration = 0;

  JustAudioEngine({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _errorSubscription = _player.errorStream.listen(_reportError);
  }

  void _reportError(Object error) {
    if (_errors.isClosed || identical(_lastError, error)) return;
    _lastError = error;
    _errors.add(error);
  }

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration> get durationStream =>
      _player.durationStream.map((duration) => duration ?? Duration.zero);

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completionStream => _player.playerStateStream
      .where((state) => state.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<void> load(PlaySource source, {Duration? initialPosition}) async {
    _playGeneration++;
    _lastError = null;
    final AudioSource audioSource = source.isLocal
        ? AudioSource.file(source.url)
        : RangeProxySource(
            key: source.key,
            url: source.url,
            backupUrl: source.backupUrl,
            headers: source.headers,
            contentType: source.contentType,
          );
    await _player.setAudioSource(audioSource, initialPosition: initialPosition);
  }

  @override
  Future<void> play() async {
    _lastError = null;
    final generation = ++_playGeneration;
    // AudioPlayer.play 直到暂停/结束才完成；不能让状态机等到那时又写回 playing=true。
    unawaited(_player.play().catchError((Object error, StackTrace _) {
      if (generation == _playGeneration) _reportError(error);
    }));
  }

  @override
  Future<void> pause() {
    _playGeneration++;
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) async {
    final previous = _player.speed;
    try {
      await _player.setSpeed(speed);
    } catch (e) {
      // just_audio 会先更新内部速度再调用平台，平台拒绝时须把内部值一并回滚。
      try {
        await _player.setSpeed(previous);
      } catch (restoreError) {
        print("恢复播放速度失败：$restoreError");
      }
      rethrow;
    }
  }

  @override
  Future<void> stop() {
    _playGeneration++;
    return _player.stop();
  }

  @override
  Future<void> dispose() async {
    _playGeneration++;
    await _errorSubscription.cancel();
    await _player.dispose();
    await _errors.close();
  }
}
