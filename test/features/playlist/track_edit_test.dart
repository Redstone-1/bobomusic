import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

/// 编辑歌曲信息（B 站等音源标题/歌手可改）：保存后列表行即时换新名，
/// 原始 name 保留（歌词匹配与下载文件名不受影响）
void main() {
  testWidgets("我喜欢列表：编辑信息改歌名，原始 name 不被覆盖", (tester) async {
    final app = await buildTestApp(
      seedTracks: const [
        {"id": "bili:1_a", "name": "UP主自拟超长标题", "author": "UP主"},
      ],
    );
    await TrackRepository().setLiked("bili:1_a", true);

    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 快捷卡进入喜欢列表
    await tester.tap(find.text("我喜欢的音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 行内更多菜单 → 编辑信息（弹层进场动画需先落一帧再点）
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("编辑信息"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 弹窗内歌名输入框（预填当前显示名），改后保存
    final nameField = find
        .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
        .first;
    await tester.enterText(nameField, "改后歌名");
    await tester.pump();
    await tester.tap(find.text("保存"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 列表行换新名；库内原始 name 保留、覆盖字段落库
    expect(
      find.descendant(
        of: find.byType(SongListTile),
        matching: find.text("改后歌名"),
      ),
      findsOneWidget,
    );
    final stored = await TrackRepository().getById("bili:1_a");
    expect(stored!.name, "UP主自拟超长标题");
    expect(stored.displayName, "改后歌名");
  });
}
