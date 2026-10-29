import "dart:async";

import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/core/theme/aurora_tokens.dart";
import "package:bobomusic/core/widgets/scale_tap.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/audio_engine.dart";
import "package:bobomusic/features/player/player_card_page.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/player/playback_speed.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";
import "../helpers/fake_engine.dart";

class _WaitingSpeedEngine extends FakeEngine {
  Completer<void>? waitForSpeed;

  @override
  Future<void> setSpeed(double value) async {
    final gate = waitForSpeed;
    waitForSpeed = null;
    if (gate != null) await gate.future;
    await super.setSpeed(value);
  }
}

Future<ProviderContainer> openPlayer(
  WidgetTester tester, {
  double width = 390,
  double textScale = 1,
  bool dark = false,
  FakeEngine? engine,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app =
      await buildTestApp(prefs: {"theme_mode": dark ? "dark" : "light"});
  if (engine != null) {
    fakePlaybackEngine = engine;
    playbackDepsTestOverride = PlaybackDeps(
      engine: engine,
      resolveSource: (track) async =>
          PlaySource(key: track.id, url: "https://fake/audio"),
    );
  }
  await tester.pumpWidget(app);
  await tester.pump();
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final notifier = container.read(playbackProvider.notifier);
  notifier.play(const Track(id: "speed", name: "歌", author: "甲"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  fakePlaybackEngine!.emitPosition(const Duration(seconds: 37));
  await tester.pump();
  Navigator.of(tester.element(find.byType(Scaffold).first)).push(
    MaterialPageRoute<void>(builder: (_) => const PlayerCardPage()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  notifier.pause();
  await tester.pump();
  return container;
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key("player_speed")));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  playbackDepsTestOverride = null;
  await appDb.close();
}

Finder get sliderFinder => find.byKey(const Key("playback_speed_slider"));
Finder get valueFinder => find.byKey(const Key("playback_speed_value"));

String shownSpeed(WidgetTester tester) =>
    tester.widget<Text>(valueFinder).textSpan!.toPlainText();

Color? speedIconColor(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byKey(const Key("player_speed")),
        matching: find.byIcon(Icons.speed_rounded),
      ),
    )
    .color;

Offset positionFor(WidgetTester tester, double value) {
  final rect = tester.getRect(sliderFinder);
  final inset = rect.width / (playbackSpeedPresets.length * 2);
  return Offset(
    rect.left + inset + (rect.width - inset * 2) * ((value - 0.5) / 1.5),
    rect.center.dy,
  );
}

Finder actionButton(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byType(ScaleTap),
    )
    .first;

void expectActionAlignment(WidgetTester tester) {
  final buttons = [
    for (final label in ["喜欢", "下载", "稍后", "倍速"])
      tester.getRect(actionButton(label)),
  ];
  final labels = [
    for (final label in ["喜欢", "下载", "稍后", "倍速"])
      tester.getRect(find.text(label)),
  ];
  final icons = [
    for (final label in ["喜欢", "下载", "稍后", "倍速"])
      tester.getRect(find.descendant(
        of: actionButton(label),
        matching: find.byType(Icon),
      )),
  ];
  final spacing = buttons[1].center.dx - buttons[0].center.dx;
  for (var i = 0; i < buttons.length; i++) {
    expect(buttons[i].width, closeTo(buttons.first.width, 0.01),
        reason: "四个入口不能随图标或文字宽度收缩");
    expect(buttons[i].height, closeTo(buttons.first.height, 0.01));
    expect(buttons[i].width, greaterThanOrEqualTo(48));
    expect(buttons[i].height, greaterThanOrEqualTo(48));
    expect(icons[i].center.dy, closeTo(icons.first.center.dy, 0.01));
    expect(labels[i].top, closeTo(labels.first.top, 0.01),
        reason: "不同大小图标不能改变文字行的位置");
    if (i > 0) {
      expect(buttons[i].center.dx - buttons[i - 1].center.dx,
          closeTo(spacing, 0.01),
          reason: "相邻入口的中心应保持等距");
    }
  }
  expect(icons[2].height, greaterThan(icons.last.height),
      reason: "稍后字形留白较多，需要单独做光学放大");
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets("倍速滑杆 $width 宽：拖动预览、松手吸附、七档刻度与恢复正常", (tester) async {
      final container = await openPlayer(
        tester,
        width: width,
        textScale: width == 390 ? 1.3 : 1,
        dark: width == 390,
      );
      final notifier = container.read(playbackProvider.notifier);
      final tokens =
          AuroraTokens.of(tester.element(find.byType(PlayerCardPage)));
      expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);
      expectActionAlignment(tester);
      await tester.tap(actionButton("喜欢"));
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expectActionAlignment(tester);
      expect(speedIconColor(tester), tokens.fgDim);
      expect(
        find.descendant(
          of: find.byKey(const Key("player_speed")),
          matching: find.text("1.0×"),
        ),
        findsNothing,
      );
      await openSheet(tester);
      final slider = tester.widget<Slider>(sliderFinder);
      expect((slider.min, slider.max, slider.divisions), (0.5, 2.0, 6));
      expect(shownSpeed(tester), "1.0 倍");

      final gesture = await tester.startGesture(positionFor(tester, 1.0));
      await gesture.moveTo(positionFor(tester, 1.41));
      await tester.pump();
      expect(shownSpeed(tester), "1.5 倍", reason: "吸附最近的 0.25 倍刻度");
      expect(container.read(playbackProvider).speed, 1.0, reason: "松手前只预览");
      expect(fakePlaybackEngine!.speed, 1.0);
      expect(appPrefs.get(playbackSpeedPreferenceKey), isNull);
      await gesture.up();
      await tester.pump();
      expect(fakePlaybackEngine!.speed, 1.5);
      expect(appPrefs.getDouble(playbackSpeedPreferenceKey), 1.5);
      expect(find.text("倍速播放"), findsOneWidget, reason: "提交后保留面板");
      expect(speedIconColor(tester), tokens.primary);

      for (final value in playbackSpeedPresets) {
        await tester.tap(find.byKey(ValueKey("playback_speed_$value")));
        await tester.pump();
        expect(tester.widget<Slider>(sliderFinder).value, value);
        expect(container.read(playbackProvider).speed, value);
        expect(fakePlaybackEngine!.speed, value);
      }
      await tester.tap(find.byKey(const Key("playback_speed_reset")));
      await tester.pump();
      expect(shownSpeed(tester), "1.0 倍");
      expect(speedIconColor(tester), tokens.fgDim);
      expect(appPrefs.getDouble(playbackSpeedPreferenceKey), 1.0);
      expect(container.read(playbackProvider).playing, isFalse);
      expect(container.read(playbackProvider).position,
          const Duration(seconds: 37));

      // 面板未拖动时跟随系统等外部调速；关闭重开仍显示真实速度。
      notifier.systemSetSpeed(1.75);
      await tester.pump();
      expect(shownSpeed(tester), "1.75 倍");
      await tester.tapAt(const Offset(10, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(sliderFinder, findsNothing);
      await openSheet(tester);
      expect(shownSpeed(tester), "1.75 倍");
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  testWidgets("平台调速失败后回显真实速度，面板保留且可重试", (tester) async {
    final container = await openPlayer(tester);
    await openSheet(tester);
    fakePlaybackEngine!.failNextSpeed = true;
    await tester.tap(find.byKey(const ValueKey("playback_speed_1.75")));
    await tester.pump();
    expect(shownSpeed(tester), "1.0 倍");
    expect(tester.widget<Slider>(sliderFinder).value, 1.0);
    expect(container.read(playbackProvider).speed, 1.0);
    expect(appPrefs.get(playbackSpeedPreferenceKey), isNull);
    expect(find.text("倍速播放"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("playback_speed_1.25")));
    await tester.pump();
    expect(shownSpeed(tester), "1.25 倍");
    expect(fakePlaybackEngine!.speed, 1.25);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets("迟到的提交不覆盖新拖动预览，关闭后的提交也不访问已销毁面板", (tester) async {
    final engine = _WaitingSpeedEngine();
    final container = await openPlayer(tester, engine: engine);
    await openSheet(tester);
    final gate = Completer<void>();
    engine.waitForSpeed = gate;
    await tester.tap(find.byKey(const ValueKey("playback_speed_1.5")));
    await tester.pump();
    expect(shownSpeed(tester), "1.5 倍");
    final gesture = await tester.startGesture(positionFor(tester, 1.5));
    await gesture.moveTo(positionFor(tester, 1.75));
    await tester.pump();
    gate.complete();
    await tester.pump();
    expect(container.read(playbackProvider).speed, 1.5);
    expect(shownSpeed(tester), "1.75 倍");
    await gesture.up();
    await tester.pump();
    expect(engine.speed, 1.75);

    final closingGate = Completer<void>();
    engine.waitForSpeed = closingGate;
    await tester.tap(find.byKey(const ValueKey("playback_speed_2.0")));
    await tester.pump();
    await tester.tapAt(const Offset(10, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(sliderFinder, findsNothing);
    closingGate.complete();
    await tester.pump();
    expect(container.read(playbackProvider).speed, 2.0);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });
}
