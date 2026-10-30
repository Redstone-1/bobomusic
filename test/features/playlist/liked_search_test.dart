import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/player_card_page.dart";
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

  testWidgets("喜欢列表：播放卡取消喜欢后返回自动刷新", (WidgetTester tester) async {
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

    await tester.tap(find.text("我喜欢的音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 播放「晴天」→ 迷你条 → 播放卡
    await tester.tap(find.text("晴天"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 播放卡取消喜欢 → 关闭返回列表
    expect(find.text("正在播放"), findsOneWidget);
    final likedIcon = find.descendant(
      of: find.byType(PlayerCardPage),
      matching: find.byIcon(Icons.favorite),
    );
    expect(likedIcon, findsOneWidget);
    await tester.tap(likedIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: find.byType(PlayerCardPage),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key("player_close")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 列表由 family provider 自动重读：取消喜欢的曲目即时消失
    // （迷你条仍显示正在播放的歌名，故只断言列表行）
    expect(
      find.descendant(of: find.byType(SongListTile), matching: find.text("晴天")),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(SongListTile), matching: find.text("夜曲")),
      findsOneWidget,
    );

    // 再次打开播放卡：喜欢态以库为准（取消后应为空心）
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlayerCardPage),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PlayerCardPage),
        matching: find.byIcon(Icons.favorite),
      ),
      findsNothing,
    );
  });

  testWidgets("喜欢列表：清除全部需二次确认，确认后清空且曲目保留", (WidgetTester tester) async {
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

    await tester.tap(find.text("我喜欢的音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 弹确认 → 取消不删
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("清除全部喜欢的歌曲？"), findsOneWidget);
    await tester.tap(find.text("取消"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("晴天"), findsOneWidget);

    // 再开确认 → 清除后列表清空，曲目数据保留
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("清除"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("已清空喜欢列表"), findsOneWidget);
    expect(find.text("晴天"), findsNothing);
    final liked = await TrackRepository().likedTracks();
    expect(liked, isEmpty);
    expect(await TrackRepository().getById("bili:1_a"), isNotNull);
  });
}
