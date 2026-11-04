import "package:bobomusic/core/widgets/app_checkbox_row.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/playlist/batch_rename_page.dart";
import "package:bobomusic/features/playlist/playlist_page.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _enterPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key("custom_playlist_more")));
  await _frames(tester);
  await tester.tap(find.text("批量重命名"));
  await _frames(tester);
}

void main() {
  testWidgets("默认清除开头数字命中即勾选，未命中条目不勾且保持原名", (tester) async {
    final app = await buildTestApp(seedTracks: const [
      {"id": "a", "name": "001 周杰伦 东方破", "author": "上传者"},
      {"id": "b", "name": "002 周杰伦 发如雪", "author": "上传者"},
      {"id": "c", "name": "8 Mile", "author": "Eminem"},
      {"id": "d", "name": "普通歌名", "author": "上传者"},
    ]);
    final p = await PlaylistRepository().create("混合歌单");
    for (final id in ["a", "b", "c", "d"]) {
      await PlaylistRepository().addTrack(p.id, id);
    }
    await tester.pumpWidget(app);
    await _frames(tester);
    await tester.tap(find.text("混合歌单"));
    await _frames(tester);
    await _enterPreview(tester);
    expect(
        tester
            .widget<AppCheckboxRow>(
                find.byKey(const ValueKey("rename_track_a")))
            .value,
        isTrue);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey("rename_track_d")), 120,
        scrollable: find
            .descendant(
                of: find.byType(BatchRenamePage),
                matching: find.byType(Scrollable))
            .first);
    await tester.pump();
    expect(
        tester
            .widget<AppCheckboxRow>(
                find.byKey(const ValueKey("rename_track_d")))
            .value,
        isFalse);
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await TrackRepository().getById("a"))!.effectiveName, "周杰伦 东方破");
    expect((await TrackRepository().getById("c"))!.effectiveName, "Mile");
    expect((await TrackRepository().getById("d"))!.displayName, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });

  testWidgets("预览取消零写入，确认后可撤销且播放进度保持", (tester) async {
    final app = await buildTestApp(seedTracks: const [
      {"id": "a", "name": "001 周杰伦 东方破", "author": "上传者"},
      {"id": "b", "name": "002 周杰伦 发如雪", "author": "上传者"},
    ]);
    final p = await PlaylistRepository().create("批量测试");
    await PlaylistRepository().addTrack(p.id, "a");
    await PlaylistRepository().addTrack(p.id, "b");
    await tester.pumpWidget(app);
    await _frames(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlaylistPage)));
    final queue = await PlaylistRepository().items(p.id);
    container.read(playbackProvider.notifier).play(queue.first, queue: queue);
    await _frames(tester);
    fakePlaybackEngine!.emitPosition(const Duration(seconds: 33));
    await tester.pump();
    final loads = fakePlaybackEngine!.loads.length;
    await tester.tap(find.text("批量测试"));
    await _frames(tester);
    await _enterPreview(tester);
    expect(find.byType(BatchRenamePage), findsOneWidget);
    expect(find.text("周杰伦 东方破 · 上传者"), findsOneWidget);
    expect((await TrackRepository().getById("a"))!.displayName, isNull);
    await tester.tap(find.text("返回歌曲列表"));
    await _frames(tester);
    expect((await TrackRepository().getById("a"))!.displayName, isNull);
    await _enterPreview(tester);
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await TrackRepository().getById("a"))!.effectiveName, "周杰伦 东方破");
    expect((await TrackRepository().getById("b"))!.effectiveName, "周杰伦 发如雪");
    expect(container.read(playbackProvider).track!.effectiveName, "周杰伦 东方破");
    expect(container.read(playbackProvider).queue.last.effectiveName,
        "周杰伦 发如雪");
    expect(
        container.read(playbackProvider).position, const Duration(seconds: 33));
    expect(fakePlaybackEngine!.loads.length, loads);
    await tester.ensureVisible(find.byKey(const Key("rename_undo")));
    await tester.tap(find.byKey(const Key("rename_undo")));
    await _frames(tester);
    expect((await TrackRepository().getById("a"))!.displayName, isNull);
    expect(
        container.read(playbackProvider).track!.effectiveName, "001 周杰伦 东方破");
    expect(fakePlaybackEngine!.loads.length, loads);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });

  testWidgets("手动编辑过的条目同样参与建议，可逐首确认", (tester) async {
    final app = await buildTestApp(seedTracks: const [
      {"id": "a", "name": "001 周杰伦 东方破", "author": "上传者"},
      {"id": "b", "name": "002 周杰伦 发如雪", "author": "上传者"},
      {"id": "c", "name": "不确定格式", "author": "上传者"},
    ]);
    final p = await PlaylistRepository().create("预览测试");
    for (final id in ["a", "b", "c"]) {
      await PlaylistRepository().addTrack(p.id, id);
    }
    await TrackRepository().updateDisplayInfo("b", name: "002 周杰伦 手动名字");
    await tester.pumpWidget(app);
    await _frames(tester);
    await tester.tap(find.text("预览测试"));
    await _frames(tester);
    await _enterPreview(tester);
    // 手动编辑不再跳过：命中规则即默认勾选
    expect(
        tester
            .widget<AppCheckboxRow>(
                find.byKey(const ValueKey("rename_track_a")))
            .value,
        isTrue);
    expect(
        tester
            .widget<AppCheckboxRow>(
                find.byKey(const ValueKey("rename_track_b")))
            .value,
        isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey("rename_edit_c")));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey("rename_edit_c")))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(const ValueKey("rename_edit_c")));
    await _frames(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, "建议歌名"), "确认后的歌名");
    await tester.tap(find.text("确认建议"));
    await _frames(tester);
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await TrackRepository().getById("b"))!.displayName,
        "周杰伦 手动名字");
    expect((await TrackRepository().getById("c"))!.displayName, "确认后的歌名");
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
}
