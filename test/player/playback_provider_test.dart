import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/play_mode.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/origin_sdk/bili/bili_api_error.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:fake_async/fake_async.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "../helpers/fake_engine.dart";

/// S4-A1 播放状态机单测：FakeEngine 全链路（装载/切歌矩阵落地/断点续播/错误态）
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // 同步 FFI：播放切歌会查播放队列（插队），异步 isolate 会让微任务 flush 等不到结果
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late FakeEngine engine;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    engine = FakeEngine();
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (t) async => PlaySource(key: t.id, url: "https://fake.audio/${t.id}"),
    );
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    playbackDepsTestOverride = null;
  });

  Track t(String id, String name) =>
      Track(id: id, name: name, author: "歌手", duration: 200, origin: OriginType.bili);

  List<Track> queue() => [t("a", "曲A"), t("b", "曲B"), t("c", "曲C")];

  Playback pb() => container.read(playbackProvider.notifier);

  PlaybackState st() => container.read(playbackProvider);

  Future<void> flush() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test("点播单曲：默认队列为自身并开播", () async {
    await pb().play(t("a", "曲A"));
    await flush();
    expect(st().track?.id, "a");
    expect(st().playing, isTrue);
    expect(st().queueIndex, 0);
    expect(engine.loads.single.source.url, "https://fake.audio/a");
    expect(engine.playCalls, 1);
  });

  test("带队列点播：下标定位正确", () async {
    await pb().play(t("b", "曲B"), queue: queue());
    await flush();
    expect(st().queueIndex, 1);
    expect(st().queue.length, 3);
  });

  test("列表循环播完自动切下一首", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    engine.emitCompletion();
    await flush();
    expect(st().track?.id, "b");
    expect(st().playing, isTrue);
  });

  test("单曲循环播完同曲重播（重新装载、进度归零）", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    engine.emitPosition(const Duration(seconds: 99));
    // 切到单曲循环（枚举序前进：listLoop→shuffle→sequential→singleLoop）
    while (st().mode != PlayMode.singleLoop) {
      await pb().cycleMode();
    }
    engine.emitCompletion();
    await flush();
    expect(st().track?.id, "a"); // 同曲
    expect(engine.loads.length, 2); // 重新装载
    expect(st().position, Duration.zero);
  });

  test("顺序播放播完队尾自然停止", () async {
    await pb().play(t("c", "曲C"), queue: queue());
    await flush();
    while (st().mode != PlayMode.sequential) {
      await pb().cycleMode();
    }
    expect(st().mode, PlayMode.sequential);
    engine.emitCompletion();
    await flush();
    expect(st().playing, isFalse);
    expect(engine.stopCalls, 1);
    expect(st().track?.id, "c"); // 保持队尾曲目（不误清）
  });

  test("列表循环手动上一首在队首绕回队尾", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    await pb().previous();
    await flush();
    expect(st().track?.id, "c");
  });

  test("随机模式：注入固定取数并避开当前曲", () async {
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (t) async => PlaySource(key: t.id, url: "https://fake.audio/${t.id}"),
      randomPick: (_) => 0,
    );
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    await pb().cycleMode(); // → shuffle
    await pb().next();
    await flush();
    // pick=0 命中当前曲 a → 避开到 1（曲B）
    expect(st().track?.id, "b");
  });

  test("seek 透传引擎并更新 state", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    await pb().seek(const Duration(seconds: 30));
    await flush();
    expect(engine.seeks.single, const Duration(seconds: 30));
    expect(st().position, const Duration(seconds: 30));
  });

  test("装载失败：error 上抛 state、不挂死不自动重试", () async {
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (t) async => throw Exception("解析失败"),
    );
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    expect(st().error, contains("解析失败"));
    expect(st().playing, isFalse);
    expect(st().buffering, isFalse);
    expect(engine.loads, isEmpty);
  });

  test("B 站 -404（视频失效）翻译成用户友好提示", () async {
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (t) async =>
          throw const BiliApiRejectError("请求被拒绝：啥都木有", code: -404),
    );
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    expect(st().error, "原视频可能已丢失（被删除或下架），换首试试吧");
  });

  test("引擎错误流：进入 error 态并暂停", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    engine.emitError("网络中断");
    await flush();
    expect(st().error, "网络中断");
    expect(st().playing, isFalse);
  });

  test("断点续播：进度去抖 5s 写盘", () async {
    fakeAsync((async) async {
      await pb().play(t("a", "曲A"), queue: queue());
      async.flushMicrotasks();
      engine.emitPosition(const Duration(seconds: 10));
      async.flushMicrotasks();
      // 5s 内未到去抖阈值：不写盘
      async.elapse(const Duration(seconds: 4));
      expect(appPrefs.getString("playback_track_id"), isNull);
      // 到 5s：写盘
      async.elapse(const Duration(seconds: 2));
      expect(appPrefs.getString("playback_track_id"), "a");
      expect(appPrefs.getInt("playback_position_ms"), 10000);
    });
  });

  test("暂停立即写盘（不等去抖）", () async {
    fakeAsync((async) async {
      await pb().play(t("a", "曲A"), queue: queue());
      async.flushMicrotasks();
      engine.emitPosition(const Duration(seconds: 20));
      async.flushMicrotasks();
      await pb().pause();
      async.flushMicrotasks();
      expect(appPrefs.getString("playback_track_id"), "a");
      expect(appPrefs.getInt("playback_position_ms"), 20000);
    });
  });

  test("冷启动断点恢复：曲目/进度/模式回填为暂停态", () async {
    // 预置：库里有曲 + prefs 有断点
    await TrackRepository().upsert(t("a", "曲A"));
    SharedPreferences.setMockInitialValues(const {
      "playback_track_id": "a",
      "playback_position_ms": 45000,
      "playback_mode": "shuffle",
    });
    await initAppPrefs();
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(playbackProvider); // 触发 build（异步恢复）
    // 恢复链路含 ffi 查库（isolate 往返不止微任务），轮询等待完成
    for (var i = 0; i < 50 && c2.read(playbackProvider).track == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final restored = c2.read(playbackProvider);
    expect(restored.track?.id, "a");
    expect(restored.position, const Duration(seconds: 45));
    expect(restored.mode, PlayMode.shuffle);
    expect(restored.playing, isFalse); // 恢复为暂停态，点播放续播
    expect(engine.loads, isEmpty); // 未触发装载
  });

  test("播放模式循环轮转并持久化", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    await pb().cycleMode(); // listLoop → shuffle
    expect(st().mode, PlayMode.shuffle);
    expect(appPrefs.getString("playback_mode"), "shuffle");
    await pb().cycleMode(); // shuffle → sequential
    await pb().cycleMode(); // sequential → singleLoop（环绕）
    expect(st().mode, PlayMode.singleLoop);
    expect(appPrefs.getString("playback_mode"), "singleLoop");
  });

  /// 等待异步查库完成（ffi 隔离线程往返，微任务 flush 不够）
  Future<void> waitFor(bool Function() predicate) async {
    for (var i = 0; i < 200 && !predicate(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  test("插队队列优先：next 先消费队列首曲并清空该行", () async {
    await TrackRepository().upsert(t("q", "队列曲"));
    await QueueRepository().append("q");
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();

    await pb().next();
    await waitFor(() => st().track?.id == "q");
    expect(st().track?.id, "q");
    expect(await QueueRepository().all(), isEmpty);
    // 插队曲插入会话队列当前位之后，后续仍可继续原列表
    expect(st().queue.map((e) => e.id).toList(), ["a", "q", "b", "c"]);
  });

  test("播完自动切歌同样先消费插队队列", () async {
    await TrackRepository().upsert(t("q", "队列曲"));
    await QueueRepository().append("q");
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();

    engine.emitCompletion();
    await waitFor(() => st().track?.id == "q");
    expect(st().track?.id, "q");
    expect(await QueueRepository().all(), isEmpty);
  });

  test("无当前曲且队列非空：toggle 从队列开播", () async {
    await TrackRepository().upsert(t("q", "队列曲"));
    await QueueRepository().append("q");

    await pb().toggle();
    await waitFor(() => st().track?.id == "q");
    expect(st().track?.id, "q");
    expect(st().playing, isTrue);
    expect(await QueueRepository().all(), isEmpty);
  });

  test("切歌前旧曲进度立即写盘（不等 5s 去抖）", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    engine.emitPosition(const Duration(seconds: 33));
    await flush();
    await pb().play(t("b", "曲B"), queue: queue());
    await flush();
    expect(appPrefs.getString("playback_track_id"), "a");
    expect(appPrefs.getInt("playback_position_ms"), 33000);
  });

  test("点播列表不含目标曲：回退单曲，不误播列表首曲", () async {
    await pb().play(t("c", "曲C"), queue: [t("a", "曲A"), t("b", "曲B")]);
    await flush();
    expect(st().track?.id, "c");
    expect(st().queue.length, 1);
  });

  test("定时关闭：到点暂停并清空定时状态", () {
    fakeAsync((async) {
      pb().play(t("a", "曲A"), queue: queue());
      async.flushMicrotasks();
      pb().setSleepAfter(const Duration(minutes: 30));
      expect(st().sleepDeadline, isNotNull);

      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();
      expect(st().playing, isFalse);
      expect(engine.pauseCalls, 1);
      expect(st().sleepDeadline, isNull);
    });
  });

  test("定时关闭：播完再停不切下一首", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    pb().setStopAfterCurrent();
    expect(st().stopAfterTrack, isTrue);

    engine.emitCompletion();
    await flush();
    expect(st().track?.id, "a");
    expect(st().playing, isFalse);
    expect(engine.stopCalls, 1);
    expect(engine.loads.length, 1);
    expect(st().stopAfterTrack, isFalse);
  });
}
