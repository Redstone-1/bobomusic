import "dart:io";

import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/origin_service.dart" as data;
import "package:bobomusic/data/repositories/history_repository.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/play_mode.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/origin_sdk/bili/bili_api_error.dart";
import "package:bobomusic/origin_sdk/origin_types.dart" as sdk;
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

  test("自动下一曲：引擎不重复发 playing 时也清缓冲并继续走进度", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    // 真实 just_audio 同一实例切源时常不再发 playing=true
    engine.emitPlayingOnPlay = false;
    engine.emitCompletion();
    await flush();

    expect(st().track?.id, "b");
    expect(st().buffering, isFalse);
    engine.emitPosition(const Duration(seconds: 12));
    await flush();
    expect(st().position, const Duration(seconds: 12));
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
    expect(st().track, isNull); // 无旧会话：整态回退后不残留失败曲
    expect(engine.loads, isEmpty);
  });

  test("装载失败：整态回退旧曲，播放条/列表不再显示没播成的新歌", () async {
    // 先正常播 A
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    expect(st().playing, isTrue);
    // 换成抛错的源解析再点 B
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (t) async => throw Exception("取流失败"),
    );
    await pb().play(t("b", "曲B"), queue: queue());
    await flush();
    expect(st().track?.id, "a"); // 回退显示旧曲
    expect(st().queue.map((e) => e.id), ["a", "b", "c"]); // 队列一并回退
    expect(st().playing, isTrue); // 旧曲仍在播（引擎旧源未被替换）
    expect(st().error, contains("取流失败"));
    expect(appPrefs.getString("playback_track_id"), "a"); // 断点也回到旧曲
  });

  test("装载失败：乐观写入的播放历史被回滚，不留「最近播放」", () async {
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (t) async => throw Exception("解析失败"),
    );
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    expect(await HistoryRepository().recent(), isEmpty);
  });

  test("装载成功：播放历史记录当前曲", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    expect((await HistoryRepository().recent()).map((e) => e.id), ["a"]);
  });

  test("冷启动恢复后点播放：走完整装载并从恢复进度续播", () async {
    // 模拟冷启动：恢复只回填 UI 不装载引擎（既有约定）
    await TrackRepository().upsert(t("a", "曲A"));
    SharedPreferences.setMockInitialValues(const {
      "playback_track_id": "a",
      "playback_position_ms": 30000,
      "playback_mode": "listLoop",
    });
    await initAppPrefs();
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(playbackProvider);
    for (var i = 0; i < 200 && c2.read(playbackProvider).track == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(c2.read(playbackProvider).playing, isFalse);
    expect(engine.loads, isEmpty);

    // 点播放：引擎无源，裸 play 无声无进度（真机反馈），必须完整装载续播
    await c2.read(playbackProvider.notifier).toggle();
    await flush();
    expect(engine.loads, hasLength(1));
    expect(engine.loads.single.source.url, "https://fake.audio/a");
    expect(engine.loads.single.initialPosition, const Duration(seconds: 30));
    expect(c2.read(playbackProvider).playing, isTrue);
  });

  test("装载阶段失败：回退强制暂停态，点播放走完整装载恢复旧曲", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    expect(st().playing, isTrue);

    // 同一引擎的下一次 load 抛错（模拟真机 load 中断旧源）
    engine.failNextLoad = true;
    await pb().play(t("b", "曲B"), queue: queue());
    await flush();
    // 引擎已被打断：回退不允许宣称仍在播（否则暂停键打到哑引擎上永久卡死）
    expect(st().track?.id, "a");
    expect(st().playing, isFalse);
    expect(st().error, isNotNull);

    // 点播放：引擎已无源 → 完整装载恢复旧曲（从展示进度续播）
    final loadsBefore = engine.loads.length;
    await pb().toggle();
    await flush();
    expect(engine.loads.length, loadsBefore + 1);
    expect(engine.loads.last.source.url, "https://fake.audio/a");
    expect(st().track?.id, "a");
    expect(st().playing, isTrue);
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

  test("暂停立即写盘（不等去抖），队列快照与曲目同刻写入", () async {
    fakeAsync((async) async {
      await pb().play(t("a", "曲A"), queue: queue());
      async.flushMicrotasks();
      engine.emitPosition(const Duration(seconds: 20));
      async.flushMicrotasks();
      await pb().pause();
      async.flushMicrotasks();
      expect(appPrefs.getString("playback_track_id"), "a");
      expect(appPrefs.getInt("playback_position_ms"), 20000);
      expect(appPrefs.getString("playback_queue_ids"), '["a","b","c"]');
      expect(appPrefs.getInt("playback_queue_index"), 0);
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

  test("冷启动恢复会话队列：快照 id 回库重建，已删曲目剔除", () async {
    await TrackRepository().upsert(t("a", "曲A"));
    await TrackRepository().upsert(t("b", "曲B"));
    SharedPreferences.setMockInitialValues(const {
      "playback_track_id": "b",
      "playback_position_ms": 10000,
      "playback_mode": "listLoop",
      // x 未入库：恢复时自动剔除；下标按当前曲定位（b → 1）
      "playback_queue_ids": '["a","x","b"]',
      "playback_queue_index": 1,
    });
    await initAppPrefs();
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(playbackProvider);
    for (var i = 0;
        i < 200 && c2.read(playbackProvider).queue.length < 2;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final restored = c2.read(playbackProvider);
    expect(restored.queue.map((e) => e.id).toList(), ["a", "b"]);
    expect(restored.queueIndex, 1);
    expect(restored.playing, isFalse);
    expect(engine.loads, isEmpty);
  });

  test("冷启动恢复：重复曲目按保存下标定位", () async {
    await TrackRepository().upsert(t("a", "曲A"));
    await TrackRepository().upsert(t("b", "曲B"));
    SharedPreferences.setMockInitialValues(const {
      "playback_track_id": "a",
      "playback_queue_ids": '["a","b","a"]',
      "playback_queue_index": 2,
      "playback_mode": "listLoop",
    });
    await initAppPrefs();
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(playbackProvider);
    for (var i = 0;
        i < 200 && c2.read(playbackProvider).queue.length < 3;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final restored = c2.read(playbackProvider);
    expect(restored.queue.map((e) => e.id).toList(), ["a", "b", "a"]);
    expect(restored.queueIndex, 2);
  });

  test("冷启动恢复：当前曲不在队列快照（或快照损坏）时退回单曲", () async {
    await TrackRepository().upsert(t("a", "曲A"));
    SharedPreferences.setMockInitialValues(const {
      "playback_track_id": "a",
      "playback_queue_ids": "not-json",
    });
    await initAppPrefs();
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(playbackProvider);
    for (var i = 0; i < 200 && c2.read(playbackProvider).track == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final restored = c2.read(playbackProvider);
    expect(restored.track?.id, "a");
    expect(restored.queue.length, 1);
    expect(restored.queueIndex, 0);
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
    await waitFor(() => appPrefs.getString("playback_track_id") == "q");
    expect(st().track?.id, "q");
    expect(await QueueRepository().all(), isEmpty);
    // 插队曲插入会话队列当前位之后，后续仍可继续原列表
    expect(st().queue.map((e) => e.id).toList(), ["a", "q", "b", "c"]);
    // takeFirst 出队后立刻持久化新会话快照（修复出队/恢复时序不一致）
    expect(appPrefs.getString("playback_queue_ids"), '["a","q","b","c"]');
    expect(appPrefs.getInt("playback_queue_index"), 1);
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

  test("切歌立即写新曲与队列快照（不等 5s 去抖）", () async {
    await pb().play(t("a", "曲A"), queue: queue());
    await flush();
    engine.emitPosition(const Duration(seconds: 33));
    await flush();
    await pb().play(t("b", "曲B"), queue: queue());
    await flush();
    // 切歌后快照必须已经是新曲 + 新下标，避免被旧曲覆盖
    expect(appPrefs.getString("playback_track_id"), "b");
    expect(appPrefs.getInt("playback_position_ms"), 0);
    expect(appPrefs.getString("playback_queue_ids"), '["a","b","c"]');
    expect(appPrefs.getInt("playback_queue_index"), 1);
  });

  test("点播列表不含目标曲：回退单曲，不误播列表首曲", () async {
    await pb().play(t("c", "曲C"), queue: [t("a", "曲A"), t("b", "曲B")]);
    await flush();
    expect(st().track?.id, "c");
    expect(st().queue.length, 1);
  });

  test("已下载曲目：localPath 存在时优先本地文件播放（离线）", () async {
    final file = File(
      "${Directory.systemTemp.path}/bobo_local_${DateTime.now().microsecondsSinceEpoch}.m4a",
    )..writeAsStringSync("audio");
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    // 只注入引擎，保留生产源解析（验证本地文件优先分支）
    playbackDepsTestOverride = PlaybackDeps(engine: engine);

    await pb().play(
      Track(
        id: "bili:downloaded",
        name: "已下载",
        author: "歌手",
        duration: 200,
        origin: OriginType.bili,
        localPath: file.path,
      ),
    );
    await flush();

    expect(engine.loads, hasLength(1));
    expect(engine.loads.single.source.isLocal, isTrue);
    expect(engine.loads.single.source.url, file.path);
  });

  test("已下载曲目：localPath 不存在于旧 Track 时回库补查并本地播放", () async {
    final file = File(
      "${Directory.systemTemp.path}/bobo_local_db_${DateTime.now().microsecondsSinceEpoch}.m4a",
    )..writeAsStringSync("audio");
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    // 库内登记下载路径；播放对象仍是“下载前”的旧 Track（无 localPath）
    await TrackRepository().upsert(
      Track(
        id: "bili:downloaded_db",
        name: "已下载",
        author: "歌手",
        duration: 200,
        origin: OriginType.bili,
        localPath: file.path,
      ),
    );
    playbackDepsTestOverride = PlaybackDeps(engine: engine);

    await pb().play(
      Track(
        id: "bili:downloaded_db",
        name: "已下载",
        author: "歌手",
        duration: 200,
        origin: OriginType.bili,
      ),
    );
    await flush();

    expect(engine.loads.single.source.isLocal, isTrue);
    expect(engine.loads.single.source.url, file.path);
  });

  test("酷我曲目：取流走 kuwoApi（不碰 B 站）", () async {
    final old = data.kuwoApi;
    addTearDown(() => data.kuwoApi = old);
    data.kuwoApi = _FakeKuwoApi();
    playbackDepsTestOverride = PlaybackDeps(engine: engine);

    await pb().play(
      Track(
        id: "kuwo:123",
        name: "酷我曲",
        author: "歌手",
        duration: 200,
        origin: OriginType.kuwo,
      ),
    );
    await flush();

    expect(engine.loads.single.source.url, "https://kuwo.example/123.mp3");
    expect(engine.loads.single.source.contentType, "audio/mpeg");
    expect(
      engine.loads.single.source.headers?["Referer"],
      "https://www.kuwo.cn/",
    );
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

/// 测试用酷我源：只实现取流（搜索页路由由 widget 测试的 Fake 覆盖）
class _FakeKuwoApi implements sdk.OriginService {
  @override
  Future<sdk.SearchResponse> search(sdk.SearchParams params) async =>
      throw UnimplementedError();

  @override
  Future<List<sdk.SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  @override
  Future<List<sdk.SearchItem>> hotSongs() async => const [];

  @override
  Future<List<sdk.ChartHit>?> getChartHits(String chartKey) async => null;

  @override
  Future<sdk.SearchItem> searchDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<sdk.MusicUrl> getMusicUrl(String id) async => sdk.MusicUrl(
        url: "https://kuwo.example/${id.split(":").last}.mp3",
        headers: const {"Referer": "https://www.kuwo.cn/"},
        contentType: "audio/mpeg",
      );
}
