import "package:bobomusic/app/desktop/desktop_shell.dart";
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

Future<ProviderContainer> _openLyrics(
    WidgetTester tester, bool expanded) async {
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
    expect(
        tester.getRect(find.byTooltip("收起播放页")).right, lessThan(viewport.left),
        reason: "收起按钮应并入左侧标题区");
  }
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets("展开播放页：左栏工具可校准歌词和打开搜索", (tester) async {
    final container = await _openLyrics(tester, true);
    await tester.tap(find.byKey(const Key("lyric_tools")));
    await _settleLyrics(tester);
    await tester.tap(find.text("歌词延后 0.5s"));
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
