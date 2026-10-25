import "dart:async";

import "package:bobomusic/features/player/audio_engine.dart";

/// 测试用播放引擎：无平台通道，事件由测试显式驱动（emit*），时间完全可控
class FakeEngine implements AudioEngine {
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completionCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();

  /// load 调用记录（源 + 断点位置），断言装载行为用
  final loads = <({PlaySource source, Duration? initialPosition})>[];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  final seeks = <Duration>[];

  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;

  @override
  Stream<void> get completionStream => _completionCtrl.stream;

  @override
  Stream<Object> get errorStream => _errorCtrl.stream;

  @override
  Future<void> load(PlaySource source, {Duration? initialPosition}) async {
    loads.add((source: source, initialPosition: initialPosition));
    position = initialPosition ?? Duration.zero;
    emitPosition(position);
    _durationCtrl.add(duration);
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
    _playingCtrl.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
    _playingCtrl.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    this.position = position;
    emitPosition(position);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
    position = Duration.zero;
    _playingCtrl.add(false);
    emitPosition(position);
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      _positionCtrl.close(),
      _durationCtrl.close(),
      _playingCtrl.close(),
      _completionCtrl.close(),
      _errorCtrl.close(),
    ]);
  }

  // ---- 测试驱动入口 ----

  void emitPosition(Duration p) {
    position = p;
    _positionCtrl.add(p);
  }

  void emitCompletion() => _completionCtrl.add(null);

  void emitError(Object e) => _errorCtrl.add(e);
}
