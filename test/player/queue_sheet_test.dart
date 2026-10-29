import "package:bot_toast/bot_toast.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/queue_entry.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/player/player_card_page.dart";
import "package:bobomusic/features/playlist/playlists_provider.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

const a = Track(id: "a", name: "会话甲", author: "歌手");
const b = Track(id: "b", name: "会话乙", author: "歌手");
const c = Track(id: "c", name: "会话丙", author: "歌手");
const q = Track(id: "q", name: "待播曲", author: "歌手");

Future<ProviderContainer> prepare(
  WidgetTester tester, {
  List<String> pending = const [],
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // 复用全局 Fake 与内存库，单独装载播放页，避免首页快捷卡影响队列布局验证。
  await buildTestApp();
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.light),
      builder: BotToastInit(),
      navigatorObservers: [BotToastNavigatorObserver()],
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  ));
  await tester.pump();
  for (final track in [a, b, c, q]) {
    await TrackRepository().upsert(track);
  }
  await QueueRepository().replaceAll(pending);
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final playback = container.read(playbackProvider.notifier);
  playback.play(b, queue: [a, b, a, c]);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  playback.pause();
  await tester.pump();
  container.invalidate(queueEntriesProvider);
  Navigator.of(tester.element(find.byType(Scaffold).first)).push(
    MaterialPageRoute<void>(builder: (_) => const PlayerCardPage()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(const Key("player_queue")));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

Finder pendingTile(QueueEntry entry) {
  final id = entry.id;
  return find.byKey(ValueKey("pending_$id"));
}

Finder sessionTile(int index) => find.byKey(ValueKey("session_$index"));

Future<void> more(WidgetTester tester, Finder tile) async {
  await tester.ensureVisible(tile);
  await tester.pump(const Duration(milliseconds: 100));
  await tester
      .tap(find.descendant(of: tile, matching: find.byType(IconButton)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  playbackDepsTestOverride = null;
  await appDb.close();
}

void main() {
  testWidgets("窄屏放大字号：打开更多及取消均不删待播数据或关闭父列表", (tester) async {
    final container =
        await prepare(tester, pending: ["q", "q", "q"], width: 320, scale: 1.3);
    final before = await QueueRepository().entries();
    await more(tester, pendingTile(before[1]));
    expect(find.text("下一首播放"), findsOneWidget);
    expect(find.text("移除本条"), findsOneWidget);
    expect((await QueueRepository().entries()).map((entry) => entry.id),
        before.map((entry) => entry.id));
    await tester.tapAt(const Offset(8, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const Key("playback_queue_sheet")), findsOneWidget);
    expect((await QueueRepository().entries()).length, 3);
    expect(container.read(playbackProvider).track?.id, "b");
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets("移除本条只删除选中重复副本，待播放列表和会话均保留", (tester) async {
    final container = await prepare(tester, pending: ["q", "q", "q"]);
    final before = await QueueRepository().entries();
    await more(tester, pendingTile(before[1]));
    await choose(tester, "移除本条");
    expect((await QueueRepository().entries()).map((entry) => entry.id),
        [before[0].id, before[2].id]);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(pendingTile(before[1]), findsNothing);
    expect(container.read(playbackProvider).track?.id, "b");
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets("待播下一首只移动该条目，随后出队消费正确的独立 id", (tester) async {
    final container = await prepare(tester, pending: ["q", "c", "q"]);
    final before = await QueueRepository().entries();
    await more(tester, pendingTile(before.last));
    await choose(tester, "下一首播放");
    expect((await QueueRepository().entries()).map((entry) => entry.id),
        [before[2].id, before[0].id, before[1].id]);
    container.read(playbackProvider.notifier).next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(playbackProvider).track?.id, "q");
    expect((await QueueRepository().entries()).map((entry) => entry.id),
        [before[0].id, before[1].id]);
    expect(find.byType(BottomSheet), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets("菜单打开期间队首已被消费，旧移除操作不会删掉下一条", (tester) async {
    final container = await prepare(tester, pending: ["q", "c"]);
    final before = await QueueRepository().entries();
    await more(tester, pendingTile(before.first));
    container.read(playbackProvider.notifier).next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await choose(tester, "移除本条");
    expect((await QueueRepository().entries()).single.id, before.last.id);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets("会话菜单移除非当前重复条目，标题数量更新且当前音频不重载", (tester) async {
    final container = await prepare(tester);
    await more(tester, sessionTile(2));
    await choose(tester, "移除本条");
    expect(container.read(playbackProvider).queue.map((track) => track.id),
        ["a", "b", "c"]);
    expect(container.read(playbackProvider).queueIndex, 1);
    expect(container.read(playbackProvider).track?.id, "b");
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(
        tester.widget<Text>(find.byKey(const Key("playback_queue_title"))).data,
        "播放队列 · 3 首");
    expect(find.byType(BottomSheet), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets("当前会话菜单实际接入下一首播放，当前条目不提供移除", (tester) async {
    final container = await prepare(tester);
    await more(tester, sessionTile(1));
    expect(find.text("移除本条"), findsNothing);
    await choose(tester, "下一首播放");
    expect((await QueueRepository().all()).single.id, "b");
    expect(container.read(playbackProvider).queue.length, 4);
    expect(fakePlaybackEngine!.loads.length, 1);
    expect(find.byType(BottomSheet), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets("待播点播失败保留记录和面板，重试成功只消费一次并保留会话", (tester) async {
    final container = await prepare(tester, pending: ["q", "q"]);
    final before = await QueueRepository().entries();
    fakePlaybackEngine!.failNextLoad = true;
    await tester.tap(pendingTile(before.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((await QueueRepository().entries()).length, 2);
    expect(container.read(playbackProvider).track?.id, "b");
    expect(find.byKey(const Key("playback_queue_sheet")), findsOneWidget);
    await tester.tap(pendingTile(before.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((await QueueRepository().entries()).single.id, before.last.id);
    expect(container.read(playbackProvider).track?.id, "q");
    expect(container.read(playbackProvider).queue.map((track) => track.id),
        ["a", "b", "q", "a", "c"]);
    expect(find.byKey(const Key("playback_queue_sheet")), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets("会话点播第二个同曲副本定位正确并关闭列表", (tester) async {
    final container = await prepare(tester);
    await tester.ensureVisible(sessionTile(2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(sessionTile(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(playbackProvider).track?.id, "a");
    expect(container.read(playbackProvider).queueIndex, 2);
    expect(find.byKey(const Key("playback_queue_sheet")), findsNothing);
    await disposeApp(tester);
  });
}
