import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/lyric_provider.dart";
import "package:bobomusic/origin_sdk/lyric/lyric_service.dart";
import "package:bobomusic/origin_sdk/lyric/lyric_types.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

class _FakeLyricService implements LyricService {
  List<LyricCandidate> candidates = const [
    LyricCandidate(
      source: LyricSource.netease,
      id: "1",
      title: "夜曲",
      artist: "周杰伦",
      durationSec: 227,
    ),
  ];
  String? raw = "[00:01.00]仿佛如同一场梦\n[00:03.00]我们如此短暂地相逢";
  int searchCalls = 0;

  @override
  Future<List<LyricCandidate>> search(String keyword) async {
    searchCalls++;
    return candidates;
  }

  @override
  Future<String?> fetch(LyricCandidate candidate) async => raw;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late _FakeLyricService fake;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await initAppPrefs();
    await initAppDatabase(path: inMemoryDatabasePath);
    fake = _FakeLyricService();
    lyricService = fake;
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  Track t(String id, {String name = "夜曲", String? lyric}) => Track(
        id: id,
        name: name,
        author: "周杰伦",
        duration: 227,
        lyric: lyric,
      );

  LyricController c() => container.read(lyricControllerProvider.notifier);

  LyricState s() => container.read(lyricControllerProvider);

  test("库内无歌词：自动匹配并写库，解析行可用", () async {
    await TrackRepository().upsert(t("a"));
    await c().loadFor(t("a"));

    expect(fake.searchCalls, 1);
    expect(s().trackId, "a");
    expect(s().lines.length, 2);
    expect(s().loading, isFalse);
    final stored = await TrackRepository().getById("a");
    expect(stored?.lyric, contains("仿佛如同一场梦"));
    expect(s().offsetMs, 0);
  });

  test("库内已有歌词：直接显示，不再搜索网络", () async {
    await TrackRepository().upsert(t("a", lyric: "[00:02.00]已有歌词"));
    await c().loadFor(t("a"));

    expect(fake.searchCalls, 0);
    expect(s().lines.single.text, "已有歌词");
  });

  test("自动匹配无候选：进入错误态但不阻塞播放", () async {
    fake.candidates = const [];
    await TrackRepository().upsert(t("a"));
    await c().loadFor(t("a"));

    expect(s().lines, isEmpty);
    expect(s().loading, isFalse);
    expect(s().error, "暂未匹配到歌词");
  });

  test("手动搜索 + 应用歌词：写库且校准归零", () async {
    await TrackRepository().upsert(t("a", lyric: "[00:02.00]旧歌词"));
    await c().loadFor(t("a"));
    await c().adjustOffset(t("a"), 800);
    expect(s().offsetMs, 800);

    await c().searchCandidates(t("a"), "夜曲 周杰伦");
    expect(s().candidates, isNotEmpty);
    fake.raw = "[00:10.00]新歌词";
    await c().applyLyric(t("a"), fake.raw!);

    expect(s().lines.single.text, "新歌词");
    expect(s().offsetMs, 0);
    final stored = await TrackRepository().getById("a");
    expect(stored?.lyric, "[00:10.00]新歌词");
    expect(stored?.lyricOffsetMs, 0);
  });

  test("校准偏移写库，并在重新加载时恢复", () async {
    await TrackRepository().upsert(t("a", lyric: "[00:02.00]词"));
    await c().loadFor(t("a"));
    await c().adjustOffset(t("a"), 1200);
    expect((await TrackRepository().getById("a"))?.lyricOffsetMs, 1200);

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    await c2.read(lyricControllerProvider.notifier).loadFor(t("a"));
    expect(c2.read(lyricControllerProvider).offsetMs, 1200);
  });

  test("删除歌词：清空库内歌词与视图", () async {
    await TrackRepository().upsert(t("a", lyric: "[00:02.00]词"));
    await c().loadFor(t("a"));
    await c().removeLyric(t("a"));

    expect(s().lines, isEmpty);
    expect((await TrackRepository().getById("a"))?.lyric, "");
  });
}
