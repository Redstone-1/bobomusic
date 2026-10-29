import "dart:async";

import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/playback_audio_handler.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/player/playback_speed.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "../helpers/fake_engine.dart";

class _DelayedSpeedEngine extends FakeEngine {
  final gate = Completer<void>();
  @override
  Future<void> setSpeed(double value) async {
    if (value == 1.5) await gate.future;
    await super.setSpeed(value);
  }
}

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const trackA = Track(id: "a", name: "甲", author: "歌手");
const trackB = Track(id: "b", name: "乙", author: "歌手");

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FakeEngine engine;

  void inject(FakeEngine value, {Future<PlaySource> Function(Track)? resolve}) {
    engine = value;
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: resolve ??
          (track) async =>
              PlaySource(key: track.id, url: "https://fake/${track.id}"),
    );
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    inject(FakeEngine());
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    playbackDepsTestOverride = null;
    playbackAudioHandler = null;
    await flush();
    await appDb.close();
  });

  Playback pb() => container.read(playbackProvider.notifier);
  PlaybackState state() => container.read(playbackProvider);

  test("偏好无曲目也能恢复，首次装载在开播前应用速度", () async {
    await appPrefs.setDouble(playbackSpeedPreferenceKey, 1.75);
    expect(state().speed, 1.75);
    await pb().play(trackA);
    expect(engine.speed, 1.75);
    expect(engine.speeds, [1.75]);
    expect(engine.playCalls, 1);
  });

  test("倍速跨切歌、暂停续播和重建保持，进度仍是歌曲时间", () async {
    await pb().play(trackA, queue: [trackA, trackB]);
    engine.emitPosition(const Duration(seconds: 30));
    await flush();
    await pb().setSpeed(1.5);
    expect(state().position, const Duration(seconds: 30));
    expect(engine.loads.length, 1);
    await pb().pause();
    expect(state().playing, isFalse);
    await pb().toggle();
    expect(engine.speed, 1.5);
    expect(engine.loads.length, 1);
    await pb().next();
    expect(state().track?.id, "b");
    expect(engine.speed, 1.5, reason: "load 会重置 Fake 平台速度，必须重新应用");
    expect(appPrefs.getDouble(playbackSpeedPreferenceKey), 1.5);
    container.dispose();
    await flush();
    inject(FakeEngine());
    container = ProviderContainer();
    expect(state().speed, 1.5);
    await flush();
    expect(state().playing, isFalse);
    await pb().toggle();
    expect(engine.speed, 1.5);
  });

  test("平台拒绝时保留上一次成功速度、偏好和播放态，后续选择仍可成功", () async {
    await pb().play(trackA);
    await pb().setSpeed(1.25);
    engine.failNextSpeed = true;
    await pb().setSpeed(1.75);
    expect(state().speed, 1.25);
    expect(engine.speed, 1.25);
    expect(state().playing, isTrue);
    expect(state().error, contains("倍速设置失败"));
    expect(appPrefs.getDouble(playbackSpeedPreferenceKey), 1.25);
    pb().clearError();
    await pb().setSpeed(2.0);
    expect(engine.speed, 2.0);
    expect(state().speed, 2.0);
  });

  test("连续选择串行生效，等待期间暂停不会被迟到结果改回播放", () async {
    final delayed = _DelayedSpeedEngine();
    inject(delayed);
    await pb().play(trackA);
    final first = pb().setSpeed(1.5);
    final last = pb().setSpeed(2.0);
    await flush();
    expect(delayed.speeds, [1.0]);
    await pb().pause();
    delayed.gate.complete();
    await Future.wait([first, last]);
    expect(delayed.speeds, [1.0, 1.5, 2.0]);
    expect(state().speed, 2.0);
    expect(state().playing, isFalse);
    expect(appPrefs.getDouble(playbackSpeedPreferenceKey), 2.0);
  });

  test("切歌解析失败回退旧曲时保留期间成功修改的全局速度", () async {
    final source = Completer<PlaySource>();
    inject(FakeEngine(), resolve: (track) async {
      if (track.id == "b") return source.future;
      return PlaySource(key: track.id, url: "https://fake/a");
    });
    await pb().play(trackA);
    final switchTrack = pb().play(trackB);
    await flush();
    await pb().setSpeed(1.5);
    source.completeError(StateError("取流失败"));
    await switchTrack;
    expect(state().track?.id, "a");
    expect(state().playing, isTrue);
    expect(state().speed, 1.5);
    expect(engine.speed, 1.5);
  });

  test("销毁后迟到的设置结果不再写状态和偏好", () async {
    final delayed = _DelayedSpeedEngine();
    inject(delayed);
    await pb().play(trackA);
    final operation = pb().setSpeed(1.5);
    await flush();
    container.dispose();
    container = ProviderContainer();
    delayed.gate.complete();
    await operation;
    expect(appPrefs.get(playbackSpeedPreferenceKey), isNull);
  });

  test("非法输入被拒绝，损坏的旧偏好恢复 1.0 倍", () async {
    await appPrefs.setString(playbackSpeedPreferenceKey, "损坏");
    expect(state().speed, 1.0);
    await pb().play(trackA);
    for (final value in [0.0, 2.1, double.nan, double.infinity]) {
      await pb().setSpeed(value);
      expect(state().speed, 1.0);
    }
    expect(engine.speeds, [1.0]);
    expect(restorePlaybackSpeed(-1), 1.0);
    expect(restorePlaybackSpeed(1.25), 1.25);
  });

  test("修改倍速不改变现实时间定时关闭的截止时间", () async {
    await pb().play(trackA);
    pb().setSleepAfter(const Duration(minutes: 30));
    final deadline = state().sleepDeadline;
    await pb().setSpeed(2.0);
    expect(state().sleepDeadline, deadline);
    pb().cancelSleep();
  });
}
