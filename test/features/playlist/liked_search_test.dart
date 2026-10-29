import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

/// 喜欢列表搜索：与本地音乐一致，有曲目时展示搜索框并实时过滤
void main() {
  testWidgets("喜欢列表：有音乐时显示搜索框，可过滤歌名", (WidgetTester tester) async {
    final app = await buildTestApp(
      seedTracks: const [
        {"id": "bili:1_a", "name": "晴天", "author": "周杰伦"},
        {"id": "bili:2_b", "name": "夜曲", "author": "周杰伦"},
      ],
    );
    await TrackRepository().setLiked("bili:1_a", true);
    await TrackRepository().setLiked("bili:2_b", true);

    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 快捷卡进入喜欢列表
    await tester.tap(find.text("我喜欢的音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("晴天"), findsOneWidget);
    expect(find.text("夜曲"), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // 输入关键词：只保留匹配行（输入框自身文本也算 Text，按列表行断言）
    await tester.enterText(find.byType(TextField), "晴天");
    await tester.pump();
    expect(
      find.descendant(of: find.byType(SongListTile), matching: find.text("晴天")),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(SongListTile), matching: find.text("夜曲")),
      findsNothing,
    );
  });
}
