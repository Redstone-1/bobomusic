import "dart:async";

import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/player/playback_volume.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "../helpers/fake_engine.dart";

class _DelayedVolumeEngine extends FakeEngine {
  final gate = Completer<void>();
  @override
  Future<void> setVolume(double value) async {
    if (value == .2) await gate.future;
    await super.setVolume(value);
  }
}

class _DelayedSeekEngine extends FakeEngine {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> seek(Duration position) async {
    entered.complete();
    await release.future;
    await super.seek(position);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FakeEngine engine;
  const track = Track(id: "volume-track", name: "音量测试", author: "歌手");
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    engine = FakeEngine();
    playbackDepsTestOverride = PlaybackDeps(
        engine: engine,
        resolveSource: (track) async =>
            PlaySource(key: track.id, url: "https://fake/audio"));
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    playbackDepsTestOverride = null;
    await Future<void>.delayed(Duration.zero);
    await appDb.close();
  });

  test("空闲调整不创建引擎，首次播放、切歌及静音恢复应用音量", () async {
    final commands = container.read(playbackProvider.notifier);
    await commands.setVolume(.4);
    expect(engine.volumes, isEmpty);
    await commands.play(track);
    expect(engine.volume, .4);
    await commands.toggleMute();
    expect(engine.volume, 0);
    await commands.toggleMute();
    expect(engine.volume, .4);
    await commands.play(const Track(id: "next", name: "下一曲", author: "歌手"));
    expect(engine.volume, .4);
    expect(appPrefs.getDouble(playbackVolumePreferenceKey), .4);
  });

  test("平台拒绝音量时保留成功值与偏好，无效音量不传给平台", () async {
    final commands = container.read(playbackProvider.notifier);
    await commands.play(track);
    await commands.setVolume(.6);
    engine.failNextVolume = true;
    await commands.setVolume(.3);
    expect(container.read(playbackProvider).volume, .6);
    expect(appPrefs.getDouble(playbackVolumePreferenceKey), .6);
    expect(container.read(playbackProvider).error, contains("音量设置失败"));
    final before = engine.volumes.length;
    await commands.setVolume(double.nan);
    await commands.setVolume(2);
    expect(engine.volumes.length, before);
  });

  test("连续调节串行应用，静音偏好重建后仍恢复上次非零值", () async {
    engine = _DelayedVolumeEngine();
    playbackDepsTestOverride = PlaybackDeps(
        engine: engine,
        resolveSource: (track) async =>
            PlaySource(key: track.id, url: "https://fake/audio"));
    final commands = container.read(playbackProvider.notifier);
    await commands.play(track);
    final first = commands.setVolume(.2);
    final second = commands.setVolume(.7);
    await Future<void>.delayed(Duration.zero);
    (engine as _DelayedVolumeEngine).gate.complete();
    await Future.wait([first, second]);
    expect(engine.volume, .7);
    await commands.toggleMute();
    container.dispose();
    container = ProviderContainer();
    expect(container.read(playbackProvider).volume, 0);
    await container.read(playbackProvider.notifier).toggleMute();
    expect(container.read(playbackProvider).volume, .7);
  });

  test("退出等待当前曲与进度快照写入，恢复为暂停态", () async {
    final commands = container.read(playbackProvider.notifier);
    await commands.play(track);
    engine.emitPosition(const Duration(seconds: 32));
    await Future<void>.delayed(Duration.zero);
    await commands.prepareForExit();
    expect(container.read(playbackProvider).playing, isFalse);
    expect(appPrefs.getInt("playback_position_ms"), 32000);
    expect(appPrefs.getString("playback_track_id"), track.id);
  });

  test("退出等待正在提交的 seek，保存最终媒体位置", () async {
    final delayed = _DelayedSeekEngine();
    engine = delayed;
    playbackDepsTestOverride = PlaybackDeps(
        engine: delayed,
        resolveSource: (track) async =>
            PlaySource(key: track.id, url: "https://fake/audio"));
    final commands = container.read(playbackProvider.notifier);
    await commands.play(track);
    final seek = commands.seek(const Duration(seconds: 45));
    await delayed.entered.future;
    var exited = false;
    final exit = commands.prepareForExit().then((_) => exited = true);
    await Future<void>.delayed(Duration.zero);
    expect(exited, isFalse);
    delayed.release.complete();
    await seek;
    await exit;
    expect(appPrefs.getInt("playback_position_ms"), 45000);
  });
}
