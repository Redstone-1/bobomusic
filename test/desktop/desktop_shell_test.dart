import "package:bobomusic/core/platform/app_platform.dart";
import "package:bobomusic/app/desktop/desktop_shell.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/features/player/desktop_player.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/player/queue_sheet.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

void main() {
  testWidgets("播放中切页和缩放不重装引擎，播放页与队列入口可操作", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await buildTestApp(platform: AppPlatform.windows));
    await tester.pump(const Duration(milliseconds: 300));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(DesktopShell)));
    var started = false;
    container
        .read(playbackProvider.notifier)
        .play(const Track(
            id: "desktop-track",
            name: "测试曲目",
            author: "歌手",
            origin: OriginType.kuwo,
            lyric: "[00:00.00]桌面歌词"))
        .then((_) => started = true);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(started, isTrue);
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(tester.takeException(), isNull);
    final panel = find.byType(DesktopNowPlayingPanel);
    await tester.tap(find.descendant(of: panel, matching: find.text("喜欢")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect((await TrackRepository().getById("desktop-track"))?.liked, isTrue);
    expect(find.descendant(of: panel, matching: find.byIcon(Icons.favorite)),
        findsOneWidget);
    // 桌面底栏和 App 动作行共享库态，外部取消喜欢后右栏也及时更新。
    await tester.tap(find.byTooltip("取消喜欢").first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        find.descendant(
            of: panel, matching: find.byIcon(Icons.favorite_border)),
        findsOneWidget);
    await tester.tap(find.descendant(of: panel, matching: find.text("稍后")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        (await QueueRepository().entries()).single.track.id, "desktop-track");
    await tester.tap(find.descendant(of: panel, matching: find.text("倍速")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey("playback_speed_1.5")));
    await tester.pump();
    expect(fakePlaybackEngine!.speed, 1.5);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey("desktop_nav_settings")));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DesktopPlayerPage), findsOneWidget);
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    for (final size in [const Size(1440, 600), const Size(800, 600)]) {
      tester.view.physicalSize = size;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: "$size");
    }
    await tester.tap(find.byTooltip("待播放").first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlaybackQueuePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });

  testWidgets("Windows 桌面导航和搜索共用现有业务，缩放不重复创建迷你条", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await buildTestApp(platform: AppPlatform.windows));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey("desktop_nav_library")), findsOneWidget);
    expect(find.byType(DesktopPlayerBar), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("desktop_nav_local")));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("本地音乐是空的"), findsOneWidget);
    expect(find.byType(DesktopPlayerBar), findsOneWidget);

    await tester.enterText(find.byKey(const Key("desktop_search")), "夜航");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("夜航西飞"), findsWidgets);
    expect(find.byType(DesktopPlayerBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final width in [1024.0, 800.0, 1800.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: "窗口宽度 $width");
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
}
