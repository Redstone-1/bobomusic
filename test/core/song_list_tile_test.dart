import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/eq_bars.dart";
import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/core/widgets/cover_placeholder.dart";
import "package:bobomusic/core/widgets/desktop_content.dart";
import "package:bobomusic/data/models/track.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  for (final desktop in [false, true]) {
    testWidgets("自定义歌曲封面在 ${desktop ? "桌面" : "手机"} 列表优先生效", (tester) async {
      final tile = SongListTile(track: const Track(id: "a", name: "歌名", author: "歌手",
          cover: "https://original/a.jpg", displayCover: "https://custom/a.jpg"));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.dark),
        home: Scaffold(body: desktop ? DesktopContent(child: tile) : tile),
      ));
      expect(tester.widget<CoverPlaceholder>(find.byType(CoverPlaceholder)).cover, "https://custom/a.jpg");
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("列表行播放中：波浪 → 心形 → 更多（波浪在心形左侧）", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.dark),
        home: Scaffold(
          body: SongListTile(
            track: const Track(
              id: "bili:test",
              name: "测试歌曲",
              author: "测试歌手",
              origin: OriginType.bili,
            ),
            playing: true,
            likedHeart: true,
            onMorePressed: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final heartX = tester.getCenter(find.byIcon(Icons.favorite)).dx;
    final waveX = tester.getCenter(find.byType(EqBars)).dx;
    final moreX = tester.getCenter(find.byIcon(Icons.more_horiz)).dx;

    expect(waveX, lessThan(heartX));
    expect(heartX, lessThan(moreX));
  });

  testWidgets("尾部图标区：盲区点击不触发行回调，心形可点，行主体点击仍有效", (tester) async {
    var rowTaps = 0;
    var heartTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.dark),
        home: Scaffold(
          body: SongListTile(
            track: const Track(
              id: "bili:test",
              name: "测试歌曲",
              author: "测试歌手",
              origin: OriginType.bili,
            ),
            playing: true,
            likedHeart: false,
            onTap: () => rowTaps++,
            onHeartTap: (_) => heartTaps++,
          ),
        ),
      ),
    );
    await tester.pump();

    // 心形点击只触发喜欢回调，不触发整行播放回调
    await tester.tap(find.byIcon(Icons.favorite_border));
    expect(heartTaps, 1);
    expect(rowTaps, 0);

    // 波浪与心形触控盒之间的盲区点击被尾部区域吸收，不触发行回调
    final gapPoint =
        tester.getTopRight(find.byType(EqBars)) + const Offset(3, 0);
    await tester.tapAt(gapPoint);
    expect(rowTaps, 0);
    expect(heartTaps, 1);

    // 行主体（标题区域）点击仍正常触发行回调
    await tester.tap(find.text("测试歌曲"));
    expect(rowTaps, 1);
    expect(heartTaps, 1);
  });
}
