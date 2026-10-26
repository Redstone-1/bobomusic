import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/eq_bars.dart";
import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/data/models/track.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("喜欢列表播放中：心形 → 波浪 → 更多，顺序不冲突", (tester) async {
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
    final moreX = tester.getCenter(find.byIcon(Icons.more_vert)).dx;

    expect(heartX, lessThan(waveX));
    expect(waveX, lessThan(moreX));
  });
}
