import "package:bobomusic/app/desktop/desktop_shell.dart";
import "package:bobomusic/core/navigation/desktop_navigation.dart";
import "package:bobomusic/core/platform/app_platform.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/lyric_provider.dart";
import "package:bobomusic/features/player/desktop_player.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/player/player_card_page.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

String _lyrics(String prefix) => List.generate(20,
        (index) => "[00:${index.toString().padLeft(2, "0")}.00]$prefix第$index句")
    .join("\n");

Future<ProviderContainer> _openLyrics(WidgetTester tester, bool expanded,
    {OriginType origin = OriginType.bili}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(await buildTestApp(platform: AppPlatform.windows));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
  await tester.pump(const Duration(milliseconds: 300));
  final container =
      ProviderScope.containerOf(tester.element(find.byType(DesktopShell)));
  var started = false;
  container
      .read(playbackProvider.notifier)
      .play(Track(
        id: "lyric-alignment",
        name: "歌词居中",
        author: "测试歌手",
        origin: origin,
        lyric: _lyrics("歌词"),
      ))
      .then((_) => started = true);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(started, isTrue);
  if (expanded) {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  }
  await _settleLyrics(tester);
  return container;
}

Future<void> _settleLyrics(WidgetTester tester) async {
  // 先交付引擎事件并完成布局，再推进歌词的滚动动画。
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder _view(bool expanded) => find.byWidgetPredicate(
    (widget) => widget is PlayerLyricsView && widget.expanded == expanded);

Finder _viewport(bool expanded) =>
    find.descendant(of: _view(expanded), matching: find.byType(ListView));

void _expectCentered(WidgetTester tester, bool expanded, String text) {
  final line = find.descendant(of: _view(expanded), matching: find.text(text));
  expect(line, findsOneWidget);
  expect(tester.getCenter(line).dy,
      closeTo(tester.getCenter(_viewport(expanded)).dy, 1),
      reason: "当前句应居中于歌词可视区域");
  if (expanded) {
    final page = tester.getRect(find.byType(DesktopPlayerPage));
    final viewport = tester.getRect(_viewport(true));
    expect(viewport.top, closeTo(page.top, 1), reason: "歌词区域应从内容区顶部开始");
    expect(viewport.bottom, closeTo(page.bottom, 1), reason: "歌词区域应铺满内容区高度");
    expect(tester.getRect(find.byKey(const Key("lyric_search"))).right,
        lessThan(viewport.left),
        reason: "搜索和校准工具应位于左栏");
    final bar = tester.getRect(find.byType(DesktopPlayerBar));
    final toggle =
        tester.getRect(find.byKey(const Key("desktop_player_expand")));
    expect(toggle.right, closeTo(bar.right - 20, 1), reason: "展开和收起入口应固定在底栏右侧");
    expect(toggle.center.dy, closeTo(bar.center.dy, 1));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets("展开页左栏无滚动，低窗口缩放封面并保留完整歌词高度", (tester) async {
    await _openLyrics(tester, true);
    final panel = find.byKey(const Key("desktop_player_artwork_panel"));
    final cover = find.byKey(const Key("desktop_player_cover"));
    for (final size in [
      const Size(1440, 900),
      const Size(1440, 600),
      const Size(800, 600),
      const Size(1024, 600),
      const Size(1800, 1050),
    ]) {
      tester.view.physicalSize = size;
      await _settleLyrics(tester);
      final bounds = tester.getRect(panel);
      final artwork = tester.getRect(cover);
      final actions =
          tester.getRect(find.byKey(const Key("desktop_track_actions")));
      expect(find.descendant(of: panel, matching: find.byType(Scrollable)),
          findsNothing);
      expect(artwork.width, closeTo(artwork.height, 1));
      expect(artwork.width, lessThanOrEqualTo(360));
      expect(artwork.top, greaterThanOrEqualTo(bounds.top));
      expect(actions.bottom, lessThanOrEqualTo(bounds.bottom));
      expect(actions.top, greaterThanOrEqualTo(artwork.bottom));
      expect(
          find.descendant(
              of: find.byType(DesktopPlayerPage), matching: find.text("正在播放")),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(DesktopPlayerPage), matching: find.text("歌词居中")),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(DesktopPlayerPage), matching: find.text("测试歌手")),
          findsNothing);
      _expectCentered(tester, true, "歌词第0句");
    }
    final before = tester.getRect(cover);
    await tester.drag(cover, const Offset(0, -120));
    await _settleLyrics(tester);
    expect(tester.getRect(cover), before);
  });

  testWidgets("展开收起共用底栏右下角入口，切换保留播放会话", (tester) async {
    final container = await _openLyrics(tester, true);
    final toggle = find.byKey(const Key("desktop_player_expand"));
    final bounds = tester.getRect(toggle);
    expect(find.byTooltip("收起播放页"), findsOneWidget);
    await tester.tap(toggle);
    await _settleLyrics(tester);
    expect(container.read(desktopNavigationProvider).route, "library");
    expect(find.byTooltip("展开播放页"), findsOneWidget);
    expect(tester.getRect(toggle), bounds);
    await tester.tap(toggle);
    await _settleLyrics(tester);
    expect(container.read(desktopNavigationProvider).route, "player");
    expect(find.byTooltip("收起播放页"), findsOneWidget);
    expect(tester.getRect(toggle), bounds);
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets("封面操作宽窗全部显示，窄窗仅将放不下的操作收进更多", (tester) async {
    await _openLyrics(tester, true, origin: OriginType.netease);
    Finder action(String label) => find.descendant(
        of: find.byKey(const Key("desktop_track_actions")),
        matching: find.byTooltip(label));
    for (final label in ["喜欢", "下载", "编辑信息", "加入歌单", "查看评论", "定时关闭"]) {
      expect(action(label), findsOneWidget);
    }
    expect(action("更多操作"), findsNothing);
    tester.view.physicalSize = const Size(800, 600);
    await _settleLyrics(tester);
    for (final label in ["喜欢", "下载", "编辑信息", "加入歌单"]) {
      expect(action(label), findsOneWidget);
    }
    expect(action("查看评论"), findsNothing);
    expect(action("定时关闭"), findsNothing);
    await tester.tap(action("更多操作"));
    await _settleLyrics(tester);
    expect(find.text("查看评论"), findsOneWidget);
    expect(find.text("定时关闭"), findsOneWidget);
    expect(find.text("下载"), findsNothing);
    expect(find.text("编辑信息"), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settleLyrics(tester);
    tester.view.physicalSize = const Size(1440, 900);
    await _settleLyrics(tester);
    expect(action("更多操作"), findsNothing);
    expect(action("查看评论"), findsOneWidget);
    expect(action("定时关闭"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("本地曲目操作不提供在线下载和评论", (tester) async {
    await _openLyrics(tester, true, origin: OriginType.local);
    final actions = find.byKey(const Key("desktop_track_actions"));
    expect(find.descendant(of: actions, matching: find.byTooltip("下载")),
        findsNothing);
    expect(find.descendant(of: actions, matching: find.byTooltip("查看评论")),
        findsNothing);
    expect(find.descendant(of: actions, matching: find.byTooltip("更多操作")),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("展开播放页：左栏工具可校准歌词和打开搜索", (tester) async {
    final container = await _openLyrics(tester, true);
    await tester.tap(find.byKey(const Key("lyric_tools")));
    await _settleLyrics(tester);
    await tester.tap(find.text("延后 0.5s"));
    await _settleLyrics(tester);
    expect(container.read(lyricControllerProvider).offsetMs, 500);
    expect(
        find.descendant(
            of: find.byType(PlayerLyricTools), matching: find.text("延后 0.5s")),
        findsOneWidget);
    await tester.tap(find.byKey(const Key("lyric_search")));
    await _settleLyrics(tester);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.hintText == "歌名 / 歌手"),
        findsOneWidget);
    await tester.tap(find.text("取消"));
    await _settleLyrics(tester);
    expect(tester.takeException(), isNull);
  });

  for (final expanded in [true, false]) {
    final label = expanded ? "展开播放页" : "右侧歌词栏";
    testWidgets("$label：首句、中间句、末句与回退都准确居中", (tester) async {
      await _openLyrics(tester, expanded);
      for (final index in [0, 9, 19, 0]) {
        fakePlaybackEngine!.emitPosition(Duration(seconds: index));
        await _settleLyrics(tester);
        _expectCentered(tester, expanded, "歌词第$index句");
      }
    });

    testWidgets("$label：暂停缩放和同一行号替换歌词后重新居中", (tester) async {
      final container = await _openLyrics(tester, expanded);
      fakePlaybackEngine!.emitPosition(const Duration(seconds: 9));
      await _settleLyrics(tester);
      _expectCentered(tester, expanded, "歌词第9句");
      await container.read(playbackProvider.notifier).pause();
      for (final height in [700.0, 1050.0]) {
        tester.view.physicalSize = Size(1440, height);
        await _settleLyrics(tester);
        _expectCentered(tester, expanded, "歌词第9句");
      }
      await tester.drag(_viewport(expanded), const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 500));
      final moved =
          find.descendant(of: _view(expanded), matching: find.text("歌词第9句"));
      expect(
          (tester.getCenter(moved).dy -
                  tester.getCenter(_viewport(expanded)).dy)
              .abs(),
          greaterThan(40));
      final track = container.read(playbackProvider).track!;
      container
          .read(lyricControllerProvider.notifier)
          .applyLyric(track, _lyrics("新版歌词"));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      _expectCentered(tester, expanded, "新版歌词第9句");
    });
  }
}
