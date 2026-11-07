import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/playlist.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/features/playlist/playlists_provider.dart";
import "package:bobomusic/features/playlist/playlist_tile.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../helpers/app_test_helper.dart";

void main() {
  Playlist pl(String id, String name) =>
      Playlist(id: id, name: name, type: PlaylistType.custom, count: 0);

  group("orderPlaylistsByPin（歌单页展示排序）", () {
    test("置顶按置顶先后排最前，未置顶按原顺序跟随", () {
      final list = [pl("a", "A"), pl("b", "B"), pl("c", "C"), pl("d", "D")];
      expect(orderPlaylistsByPin(list, ["c", "a"]).map((p) => p.id),
          ["c", "a", "b", "d"]);
    });

    test("已删歌单的残留置顶 id 被过滤，不影响其余排序", () {
      final list = [pl("a", "A"), pl("b", "B")];
      expect(orderPlaylistsByPin(list, ["ghost", "b"]).map((p) => p.id),
          ["b", "a"]);
    });

    test("无置顶时保持目录原顺序", () {
      final list = [pl("a", "A"), pl("b", "B")];
      expect(orderPlaylistsByPin(list, []).map((p) => p.id), ["a", "b"]);
    });
  });

  group("PinnedPlaylists（置顶上限与持久化）", () {
    test("最多置顶 3 个，取消后腾位可再置顶，写回 prefs", () async {
      SharedPreferences.setMockInitialValues({});
      await initAppPrefs();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final pin = container.read(pinnedPlaylistsProvider.notifier);

      expect(pin.toggle("1"), isTrue);
      expect(pin.toggle("2"), isTrue);
      expect(pin.toggle("3"), isTrue);
      // 第 4 个被拒，已置顶顺序保持
      expect(pin.toggle("4"), isFalse);
      expect(container.read(pinnedPlaylistsProvider), ["1", "2", "3"]);

      // 取消中间一个，新置顶追加到尾部
      expect(pin.toggle("2"), isTrue);
      expect(container.read(pinnedPlaylistsProvider), ["1", "3"]);
      expect(pin.toggle("4"), isTrue);
      expect(container.read(pinnedPlaylistsProvider), ["1", "3", "4"]);

      // 持久化写回：失效重读（模拟重启）仍是同一顺序
      expect(appPrefs.getStringList("pinned_playlists"), ["1", "3", "4"]);
      container.invalidate(pinnedPlaylistsProvider);
      expect(container.read(pinnedPlaylistsProvider), ["1", "3", "4"]);
    });
  });

  group("歌单页置顶（widget 集成）", () {
    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets("android 置顶歌单排到区块首位，取消后回原顺序", (tester) async {
      final app = await buildTestApp();
      for (var i = 1; i <= 3; i++) {
        await PlaylistRepository().create("测试歌单$i");
      }
      await tester.pumpWidget(app);
      await frames(tester);

      // 默认按目录顺序：歌单1 → 歌单2 → 歌单3
      double top(String name) => tester.getRect(find.text(name)).top;
      expect(top("测试歌单1"), lessThan(top("测试歌单3")));

      // 点第 3 个的置顶按钮（描边 pin）→ 排到首位，图标转实心
      Finder tilePin(String name, IconData icon) => find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(PlaylistTile)),
          matching: find.byIcon(icon));
      await tester.tap(tilePin("测试歌单3", Icons.push_pin_outlined));
      await frames(tester);
      expect(top("测试歌单3"), lessThan(top("测试歌单1")));
      expect(tilePin("测试歌单3", Icons.push_pin), findsOneWidget);

      // 取消置顶 → 回目录原顺序
      await tester.tap(tilePin("测试歌单3", Icons.push_pin));
      await frames(tester);
      expect(top("测试歌单1"), lessThan(top("测试歌单3")));
      expect(find.byType(PlaylistTile), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await appDb.close();
    });
  });
}
