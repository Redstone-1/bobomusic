import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/widgets/cover_placeholder.dart";
import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

/// 点列表封面 = 加入待播放队列（有播放条）；封面点击不触发整行点播
void main() {
  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets("有会话时点封面追加到待播队尾，行点击不被误触", (tester) async {
    final app = await buildTestApp(seedTracks: [
      {"id": "s1", "name": "测试一", "author": "歌手"},
      {"id": "s2", "name": "测试二", "author": "歌手"},
    ]);
    final playlist = await PlaylistRepository().create("飞入歌单");
    await PlaylistRepository().addTrack(playlist.id, "s1");
    await PlaylistRepository().addTrack(playlist.id, "s2");
    await tester.pumpWidget(app);
    await frames(tester);

    // 进歌单详情
    await tester.tap(find.text("飞入歌单"));
    await frames(tester);
    expect(find.text("测试二"), findsOneWidget);

    // 点第一首行 = 点播（会话队列 [s1, s2]），迷你播放条出现
    await tester.tap(find.text("测试一"));
    await frames(tester);
    expect(find.byKey(const Key("mini_player")), findsOneWidget);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(App)));
    expect(container.read(playbackProvider).track?.id, "s1");

    // 点第二首封面 → 追加待播队尾，当前播放不被打断
    final tile2 = find.ancestor(
        of: find.text("测试二"), matching: find.byType(SongListTile));
    final cover2 =
        find.descendant(of: tile2, matching: find.byType(CoverPlaceholder));
    expect(cover2, findsOneWidget);
    await tester.tap(cover2);
    // 飞入动画 550ms 收尾（播放波浪是常驻动画，禁 pumpAndSettle）
    await tester.pump(const Duration(milliseconds: 600));

    final entries = await QueueRepository().entries();
    expect(entries.map((entry) => entry.track.id), ["s2"]);
    expect(container.read(playbackProvider).track?.id, "s1");

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
}
