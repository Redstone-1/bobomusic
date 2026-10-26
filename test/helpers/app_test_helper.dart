import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart" as models;
import "package:bobomusic/data/origin_service.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/origin_sdk/bili/types.dart" as bili;
import "package:bobomusic/origin_sdk/lyric/lyric_service.dart";
import "package:bobomusic/origin_sdk/lyric/lyric_types.dart";
import "package:bobomusic/origin_sdk/origin_types.dart" as sdk;
import "package:flutter/widgets.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "fake_engine.dart";

/// 测试用 Fake B 站 API：搜索固定返回「夜航西飞」单曲，避免真实网络
class FakeBiliApi implements sdk.OriginService {
  @override
  Future<sdk.SearchResponse> search(sdk.SearchParams params) async {
    // 单曲结果
    final single = bili.BiliSearchItem(
      id: "100_BVfake",
      cover: "",
      name: "夜航西飞",
      duration: 252,
      author: "陈鸿宇",
      origin: sdk.OriginType.bili,
      isSeasonDisplay: false,
      ugcSeason: null,
    );
    // 多P歌单结果（收藏闭环用）
    final multiP = bili.BiliSearchItem(
      id: "200_BVorder",
      cover: "",
      name: "华语民谣·深夜电台",
      duration: 0,
      author: "合集作者",
      origin: sdk.OriginType.bili,
      isSeasonDisplay: false,
      ugcSeason: null,
      musicList: [
        sdk.MusicItem(
          id: "200_BVorder_1",
          cover: "",
          name: "夜曲-周杰伦",
          duration: 227,
          author: "无损音乐合集",
          origin: sdk.OriginType.bili,
        ),
        sdk.MusicItem(
          id: "200_BVorder_2",
          cover: "",
          name: "七里香",
          duration: 240,
          author: "无损音乐合集",
          origin: sdk.OriginType.bili,
        ),
      ],
    );
    return bili.BiliSearchResponse(
      current: 1,
      total: 2,
      pageSize: 20,
      data: [multiP, single],
    );
  }

  @override
  Future<List<sdk.SearchSuggestItem>> searchSuggest(String keyword) async => [];

  @override
  Future<List<sdk.SearchItem>> hotSongs() async => const [];

  @override
  Future<sdk.SearchItem> searchDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<sdk.MusicUrl> getMusicUrl(String id) async =>
      throw UnimplementedError();
}

/// 测试用酷我源：搜索固定返回「酷我夜曲」，避免真实网络
class FakeKuwoApi implements sdk.OriginService {
  @override
  Future<sdk.SearchResponse> search(sdk.SearchParams params) async {
    return bili.BiliSearchResponse(
      current: 1,
      total: 1,
      pageSize: 20,
      data: [
        bili.BiliSearchItem(
          id: "kuwo:999",
          cover: "",
          name: "酷我夜曲",
          duration: 200,
          author: "酷我歌手",
          origin: sdk.OriginType.kuwo,
          isSeasonDisplay: false,
          ugcSeason: null,
        ),
      ],
    );
  }

  @override
  Future<List<sdk.SearchSuggestItem>> searchSuggest(String keyword) async =>
      const [];

  @override
  Future<List<sdk.SearchItem>> hotSongs() async => [
        const sdk.SearchItem(
          id: "kuwo:hot_1",
          cover: "",
          name: "酷我热歌",
          duration: 200,
          author: "酷我歌手",
          origin: sdk.OriginType.kuwo,
          isSeasonDisplay: false,
          type: sdk.SearchType.music,
        ),
      ];

  @override
  Future<sdk.SearchItem> searchDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<sdk.MusicUrl> getMusicUrl(String id) async =>
      sdk.MusicUrl(url: "https://kuwo.example/999.mp3");
}

/// 测试用歌词服务：返回固定 LRC，避免真实网络；保留播放卡歌词视图断言用行
class FakeLyricService implements LyricService {
  int searchCalls = 0;
  int fetchCalls = 0;

  @override
  Future<List<LyricCandidate>> search(String keyword) async {
    searchCalls++;
    return const [
      LyricCandidate(
        source: LyricSource.netease,
        id: "lyric_1",
        title: "夜曲-周杰伦",
        artist: "无损音乐合集",
        durationSec: 227,
      ),
    ];
  }

  @override
  Future<String?> fetch(LyricCandidate candidate) async {
    fetchCalls++;
    return "[00:01.00]仿佛如同一场梦\n[00:05.00]我们如此短暂地相逢";
  }
}

/// 测试专用：mock SharedPreferences + ffi 内存库 + Fake BiliApi + mock 歌手
/// + FakeEngine 播放依赖（全部环境单例可替换：FakeAsync 下真实 I/O 不会完成）
/// 播放引擎暴露在 [fakePlaybackEngine] 供用例驱动进度/播完事件
FakeEngine? fakePlaybackEngine;

Future<Widget> buildTestApp({
  Map<String, Object> prefs = const {},
  List<Map<String, Object>> seedTracks = const [],
}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate; // 同步 FFI：微任务内完成
  SharedPreferences.setMockInitialValues(prefs);
  await initAppPrefs();
  await initAppDatabase(path: inMemoryDatabasePath);
  biliApi = FakeBiliApi();
  kuwoApi = FakeKuwoApi();
  lyricService = FakeLyricService();
  fakePlaybackEngine = FakeEngine();
  playbackDepsTestOverride = PlaybackDeps(
    engine: fakePlaybackEngine!,
    resolveSource: (track) async => PlaySource(
      key: track.id,
      url: "https://fake.audio/${track.id}",
    ),
  );
  for (final row in seedTracks) {
    await TrackRepository().upsert(
      models.Track(
        id: row["id"] as String,
        name: row["name"] as String,
        author: (row["author"] ?? "") as String,
        origin: models.OriginType.bili,
      ),
    );
  }
  return ProviderScope(child: const App());
}
