import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart" as models;
import "package:bobomusic/data/origin_service.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/data/singers_provider.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/origin_sdk/bili/types.dart" as bili;
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
  Future<sdk.SearchItem> searchDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<sdk.MusicUrl> getMusicUrl(String id) async =>
      throw UnimplementedError();
}

/// 测试用热门歌手（与真实 chinese.json 同构）
final _mockSingers = [
  SingerEntry(id: "s1", name: "周杰伦", desc: "", tracks: const [
    models.Track(
      id: "s1_t1",
      name: "夜曲-周杰伦",
      author: "无损音乐合集",
      duration: 227,
      origin: models.OriginType.bili,
    ),
    models.Track(
      id: "s1_t2",
      name: "七里香",
      author: "无损音乐合集",
      duration: 240,
      origin: models.OriginType.bili,
    ),
  ]),
  SingerEntry(id: "s2", name: "柳爽", desc: "", cover: "https://example.com/liushuang.jpg", tracks: const [
    models.Track(
      id: "s2_t1",
      name: "漠河舞厅",
      author: "柳爽",
      duration: 311,
      origin: models.OriginType.bili,
    ),
  ]),
];

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
  hotSingersTestOverride = _mockSingers;
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
