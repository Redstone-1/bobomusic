import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

void main() {
  testWidgets("长歌词切换倍速保留位置、加速滚动，暂停停止且 LRC 仍用媒体时间", (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final notifier = container.read(playbackProvider.notifier);
    const line = "这一句很长很长的歌词会一直向左滚动，途中切换倍速也应该保留当前位置，让后面的文字继续顺畅显示直到看见最后一个字";
    notifier.play(const Track(
      id: "long-lyric",
      name: "长歌词",
      author: "歌手",
      lyric: "[00:00.00]$line\n[01:00.00]下一句",
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text(line), findsOneWidget);
    double x() => tester
        .widget<Transform>(find
            .ancestor(
              of: find.text(line),
              matching: find.byType(Transform),
            )
            .first)
        .transform
        .getTranslation()
        .x;
    final before = x();
    await tester.pump(const Duration(milliseconds: 500));
    final normal = x();
    expect(normal, lessThan(before));

    notifier.setSpeed(2.0);
    await tester.pump();
    final changed = x();
    expect(changed, closeTo(normal, 0.01), reason: "变速不能让歌词重新从头滚动");
    await tester.pump(const Duration(milliseconds: 500));
    final fasterDistance = changed - x();
    expect(fasterDistance, greaterThan((before - normal) * 1.6));

    notifier.pause();
    await tester.pump();
    final paused = x();
    await tester.pump(const Duration(milliseconds: 500));
    expect(x(), closeTo(paused, 0.01));
    fakePlaybackEngine!.emitPosition(const Duration(seconds: 61));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("下一句"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
