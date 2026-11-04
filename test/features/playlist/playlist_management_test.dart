import "package:bobomusic/core/platform/app_platform.dart";
import "package:bobomusic/core/widgets/app_search_field.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/playlist/all_playlists_page.dart";
import "package:bobomusic/features/playlist/playlist_tile.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  for (final platform in [AppPlatform.android, AppPlatform.windows]) {
    testWidgets("$platform 首页只展示三项，全部歌单可搜索并打开", (tester) async {
      if (platform == AppPlatform.windows) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final app = await buildTestApp(platform: platform);
      for (var i = 1; i <= 4; i++) {
        await PlaylistRepository().create("测试歌单$i");
      }
      await tester.pumpWidget(app);
      await _frames(tester);
      expect(find.byType(PlaylistTile), findsNWidgets(3));
      await tester.tap(find.text("查看全部（共 4 个）›"));
      await _frames(tester);
      expect(find.byType(AllPlaylistsPage), findsOneWidget);
      expect(find.byType(AppSearchField), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key("all_playlists_search")), "歌单4");
      await _frames(tester);
      expect(find.byType(PlaylistTile), findsOneWidget);
      await tester.tap(find.byTooltip("清除搜索"));
      await _frames(tester);
      expect(find.byType(PlaylistTile), findsNWidgets(4));
      await tester.enterText(find.byKey(const Key("all_playlists_search")), "歌单4");
      await _frames(tester);
      await tester.tap(find.text("测试歌单4"));
      await _frames(tester);
      expect(find.text("歌单还是空的"), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await appDb.close();
    });
  }

  for (final count in [0, 3]) {
    testWidgets("$count 个歌单时无需查看全部入口", (tester) async {
      final app = await buildTestApp();
      for (var i = 0; i < count; i++) {
        await PlaylistRepository().create("歌单$i");
      }
      await tester.pumpWidget(app);
      await _frames(tester);
      expect(find.byType(PlaylistTile), findsNWidgets(count));
      expect(find.textContaining("查看全部"), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await appDb.close();
    });
  }

  testWidgets("详情编辑歌单名称及批量封面，保存后标题和曲目同步", (tester) async {
    final app = await buildTestApp(seedTracks: const [
      {"id": "a", "name": "原曲名", "author": "原歌手"}
    ]);
    final p = await PlaylistRepository().create("旧歌单");
    await PlaylistRepository().addTrack(p.id, "a");
    await TrackRepository()
        .updateDisplayInfo("a", name: "自定义曲名", author: "自定义歌手");
    await tester.pumpWidget(app);
    await _frames(tester);
    await tester.tap(find.text("旧歌单"));
    await _frames(tester);
    await tester.tap(find.byKey(const Key("custom_playlist_more")));
    await _frames(tester);
    await tester.tap(find.text("编辑信息"));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key("playlist_edit_name")), "新歌单");
    await tester.enterText(find.byKey(const Key("playlist_edit_cover")),
        "https://example.com/new.jpg");
    await tester.pump();
    await tester.tap(find.byKey(const Key("playlist_apply_cover")));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key("playlist_edit_save")));
    await tester.tap(find.byKey(const Key("playlist_edit_save")));
    await _frames(tester);
    expect(find.text("新歌单"), findsOneWidget);
    final track = (await TrackRepository().getById("a"))!;
    expect(track.effectiveCover, "https://example.com/new.jpg");
    expect(track.effectiveName, "自定义曲名");
    expect(track.effectiveAuthor, "自定义歌手");
    expect((await PlaylistRepository().getById(p.id))!.customCover,
        "https://example.com/new.jpg");
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
}
