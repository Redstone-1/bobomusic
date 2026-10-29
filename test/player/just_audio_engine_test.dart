import "dart:async";

import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/just_audio_engine.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

/// 保留真实 AudioPlayer 的 Future 语义，不再用立即完成的 play 掩盖适配问题。
class LifecyclePlayer extends Fake implements AudioPlayer {
  final errors = StreamController<PlayerException>.broadcast();
  final playingEvents = StreamController<bool>.broadcast();
  Completer<void>? active;
  bool playingNow = false;
  Object? playError;
  int loads = 0;
  @override
  double speed = 1.0;
  final speedCalls = <double>[];
  double? rejectedSpeed;

  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<bool> get playingStream => playingEvents.stream;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() {
    if (playError != null) return Future.error(playError!);
    if (playingNow) return Future.value();
    playingNow = true;
    playingEvents.add(true);
    active = Completer<void>();
    return active!.future;
  }

  @override
  Future<void> pause() async {
    playingNow = false;
    playingEvents.add(false);
    active?.complete();
    active = null;
  }

  @override
  Future<void> setSpeed(double value) async {
    speedCalls.add(value);
    speed = value; // 模拟 just_audio 在平台确认之前先修改内部值。
    if (value == rejectedSpeed) throw StateError("平台不支持该速度");
  }

  @override
  Future<void> dispose() async {
    if (active?.isCompleted == false) active!.complete();
    await errors.close();
    await playingEvents.close();
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("play 命令不等待整曲，异步失败通过 errorStream", () async {
    final player = LifecyclePlayer();
    final engine = JustAudioEngine(player: player);
    await engine.play().timeout(const Duration(seconds: 1));
    expect(player.active!.isCompleted, isFalse);
    final nextError = engine.errorStream.first;
    final failure = StateError("播放启动失败");
    player.active!.completeError(failure);
    player.active = null;
    expect(await nextError, same(failure));
    await engine.dispose();
  });

  test("立即拒绝的播放 Future 也被接住，不产生未处理异常", () async {
    final failure = StateError("音频会话不可用");
    final player = LifecyclePlayer()..playError = failure;
    final engine = JustAudioEngine(player: player);
    final error = engine.errorStream.first;
    await engine.play();
    expect(await error, same(failure));
    await engine.dispose();
  });

  test("调整速度不等待播放结束，也不重新装载音源", () async {
    final player = LifecyclePlayer();
    final engine = JustAudioEngine(player: player);
    await engine.play();
    final active = player.active;
    await engine.setSpeed(1.5);
    expect(player.speed, 1.5);
    expect(player.active, same(active));
    expect(active!.isCompleted, isFalse);
    expect(player.loads, 0);
    await engine.dispose();
  });

  test("平台拒绝速度时回滚 just_audio 已乐观修改的内部速度", () async {
    final player = LifecyclePlayer()..rejectedSpeed = 1.5;
    final engine = JustAudioEngine(player: player);
    await expectLater(engine.setSpeed(1.5), throwsA(isA<StateError>()));
    expect(player.speed, 1.0);
    expect(player.speedCalls, [1.5, 1.0]);
    await engine.dispose();
  });

  test("新源装载后旧 play Future 的迟到错误不污染新会话", () async {
    final player = LifecyclePlayer();
    final engine = JustAudioEngine(player: player);
    final errors = <Object>[];
    final subscription = engine.errorStream.listen(errors.add);
    await engine.play();
    final old = player.active!;
    await engine
        .load(const PlaySource(key: "new", url: "unused", isLocal: true));
    old.completeError(StateError("旧源被中断"));
    player.active = null;
    await flush();
    expect(errors, isEmpty);
    await subscription.cancel();
    await engine.dispose();
  });

  test("启动立即拒绝后保持失败态，清提示后重试仍会重新装载", () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    final player = LifecyclePlayer()..playError = StateError("启动拒绝");
    final engine = JustAudioEngine(player: player);
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (track) async =>
          PlaySource(key: track.id, url: "unused", isLocal: true),
    );
    final container = ProviderContainer();
    try {
      final notifier = container.read(playbackProvider.notifier);
      await notifier.play(const Track(
          id: "a", name: "歌", author: "甲", origin: OriginType.bili));
      await flush();
      expect(container.read(playbackProvider).playing, isFalse);
      expect(container.read(playbackProvider).error, contains("启动拒绝"));
      notifier.clearError();
      player.playError = null;
      await notifier.toggle();
      await flush();
      expect(player.loads, 2);
      expect(container.read(playbackProvider).playing, isTrue);
    } finally {
      container.dispose();
      playbackDepsTestOverride = null;
      await flush();
      await appDb.close();
    }
  });

  test("状态机完成装载后可暂停，生命周期 Future 结束不会重新改为播放", () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    final player = LifecyclePlayer();
    final engine = JustAudioEngine(player: player);
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (track) async =>
          PlaySource(key: track.id, url: "unused", isLocal: true),
    );
    final container = ProviderContainer();
    try {
      final notifier = container.read(playbackProvider.notifier);
      await notifier
          .play(const Track(
              id: "a", name: "歌", author: "甲", origin: OriginType.bili))
          .timeout(const Duration(seconds: 1));
      await flush();
      expect(container.read(playbackProvider).buffering, isFalse);
      await notifier.pause();
      await flush();
      expect(player.playingNow, isFalse);
      expect(container.read(playbackProvider).playing, isFalse);
      await notifier.toggle();
      await flush();
      expect(player.loads, 1, reason: "恢复播放不应重新装载同曲");
      expect(container.read(playbackProvider).playing, isTrue);
    } finally {
      container.dispose();
      playbackDepsTestOverride = null;
      await flush();
      await appDb.close();
    }
  });
}
