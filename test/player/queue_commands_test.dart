import "dart:convert";

import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "../helpers/fake_engine.dart";

const a = Track(id: "a", name: "会话甲", author: "歌手");
const b = Track(id: "b", name: "会话乙", author: "歌手");
const c = Track(id: "c", name: "会话丙", author: "歌手");
const q = Track(id: "q", name: "待播曲", author: "歌手");

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FakeEngine engine;
  late QueueRepository pending;
  var rejectPendingSource = false;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    for (final track in [a, b, c, q]) {
      await TrackRepository().upsert(track);
    }
    engine = FakeEngine();
    rejectPendingSource = false;
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (track) async {
        if (track.id == q.id && rejectPendingSource) throw StateError("取流失败");
        return PlaySource(key: track.id, url: "https://fake/audio");
      },
    );
    container = ProviderContainer();
    pending = QueueRepository();
  });

  tearDown(() async {
    container.dispose();
    await flush();
    playbackDepsTestOverride = null;
    await appDb.close();
  });
  Playback playback() => container.read(playbackProvider.notifier);
  PlaybackState state() => container.read(playbackProvider);

  test("待播点播成功只消费选中副本，插入会话并保留原列表", () async {
    await playback().play(b, queue: [a, b, c]);
    await pending.replaceAll(["q", "q", "q"]);
    final entries = await pending.entries();
    expect(await playback().playQueuedEntry(entries[1].id), isTrue);
    expect((await pending.entries()).map((entry) => entry.id),
        [entries[0].id, entries[2].id]);
    expect(state().queue.map((track) => track.id), ["a", "b", "q", "c"]);
    expect(state().queueIndex, 2);
    expect(state().track?.id, "q");
    expect(state().playing, isTrue);
    expect(appPrefs.getInt("playback_queue_index"), 2);
  });

  test("待播取流失败保留排队记录与旧会话播放", () async {
    await playback().play(b, queue: [a, b, c]);
    await pending.append("q");
    final entry = (await pending.entries()).single;
    rejectPendingSource = true;
    expect(await playback().playQueuedEntry(entry.id), isFalse);
    expect((await pending.entries()).single.id, entry.id);
    expect(state().track?.id, "b");
    expect(state().queue.map((track) => track.id), ["a", "b", "c"]);
    expect(state().playing, isTrue);
  });

  test("待播装载失败保留排队记录，旧会话回退暂停", () async {
    await playback().play(b, queue: [a, b, c]);
    await pending.append("q");
    final entry = (await pending.entries()).single;
    engine.failNextLoad = true;
    expect(await playback().playQueuedEntry(entry.id), isFalse);
    expect((await pending.entries()).single.id, entry.id);
    expect(state().track?.id, "b");
    expect(state().playing, isFalse);
  });

  test("已经出队的条目不再次点播或影响其它排队记录", () async {
    await playback().play(b, queue: [a, b, c]);
    await pending.replaceAll(["q", "c"]);
    final entry = (await pending.entries()).first;
    await pending.takeFirst();
    expect(await playback().playQueuedEntry(entry.id), isFalse);
    expect(engine.loads.length, 1);
    expect((await pending.all()).single.id, "c");
    expect(state().track?.id, "b");
  });

  test("会话按下标删除一个重复条目，前方删除修正下标且不重载音频", () async {
    await playback().play(b, queue: [a, b, a, c]);
    engine.emitPosition(const Duration(seconds: 37));
    await flush();
    expect(
        playback().removeSessionEntry(2, expectedQueue: state().queue), isTrue);
    expect(state().queue.map((track) => track.id), ["a", "b", "c"]);
    expect(state().queueIndex, 1);
    expect(
        playback().removeSessionEntry(0, expectedQueue: state().queue), isTrue);
    expect(state().queue.map((track) => track.id), ["b", "c"]);
    expect(state().queueIndex, 0);
    expect(state().position, const Duration(seconds: 37));
    expect(state().playing, isTrue);
    expect(engine.loads.length, 1);
    expect(jsonDecode(appPrefs.getString("playback_queue_ids")!), ["b", "c"]);
  });

  test("当前播放条目与过期会话下标不会被移除", () async {
    await playback().play(b, queue: [a, b, a, c]);
    final old = state().queue;
    expect(playback().removeSessionEntry(1, expectedQueue: old), isFalse);
    expect(playback().removeSessionEntry(0, expectedQueue: old), isTrue);
    expect(playback().removeSessionEntry(2, expectedQueue: old), isFalse);
    expect(state().queue.map((track) => track.id), ["b", "a", "c"]);
    expect(state().track?.id, "b");
    expect(state().playing, isTrue);
  });

  test("会话点播能定位第二个同曲条目，避免回到第一个副本", () async {
    await playback().play(b, queue: [a, b, a, c]);
    expect(await playback().playSessionEntry(2, expectedQueue: state().queue),
        isTrue);
    expect(state().track?.id, "a");
    expect(state().queueIndex, 2);
    expect(appPrefs.getInt("playback_queue_index"), 2);
  });

  test("会话移除结果跨容器恢复，当前曲目与进度保持", () async {
    await playback().play(b, queue: [a, b, c]);
    engine.emitPosition(const Duration(seconds: 37));
    await flush();
    playback().removeSessionEntry(0, expectedQueue: state().queue);
    container.dispose();
    await flush();
    engine = FakeEngine();
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (track) async =>
          PlaySource(key: track.id, url: "https://fake/audio"),
    );
    container = ProviderContainer();
    state();
    await flush();
    expect(state().queue.map((track) => track.id), ["b", "c"]);
    expect(state().queueIndex, 0);
    expect(state().position, const Duration(seconds: 37));
    expect(state().playing, isFalse);
  });
}
