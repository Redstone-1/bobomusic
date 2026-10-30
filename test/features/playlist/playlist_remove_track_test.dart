import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

/// 歌单详情行内「移出歌单」：列表与库同步移除，曲目本身保留
void main() {
  testWidgets("移出歌单后详情清空，曲目数据保留", (tester) async {
    final app = await buildTestApp(
      seedTracks: const [
        {"id": "bili:1_a", "name": "晴天", "author": "周杰伦"},
      ],
    );
    final pl = await PlaylistRepository().create("测试歌单");
    await PlaylistRepository().addTrack(pl.id, "bili:1_a");

    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 歌单页（默认落地页）→ 打开歌单详情
    await tester.tap(find.text("测试歌单"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("晴天"), findsOneWidget);

    // 行内更多 → 移出歌单
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("移出歌单"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("已移出歌单"), findsOneWidget);
    final items = await PlaylistRepository().items(pl.id);
    expect(items, isEmpty);
    expect(find.text("歌单还是空的"), findsOneWidget);
    // 曲目本身保留，可再次通过加入歌单加回
    expect(await TrackRepository().getById("bili:1_a"), isNotNull);
  });
}
