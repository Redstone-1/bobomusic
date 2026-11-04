import "dart:async";

import "package:bobomusic/core/platform/app_platform.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/playlist/batch_rename_page.dart";
import "package:bobomusic/features/playlist/playlist_tile.dart";
import "package:bobomusic/features/playlist/playlists_provider.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite/sqflite.dart";

import "../../helpers/app_test_helper.dart";

class _DatabaseProbe implements Database {
  _DatabaseProbe(this.inner, {this.failAfterCommit, this.releaseCommit});
  final Database inner;
  final int? failAfterCommit;
  final Completer<void>? releaseCommit;
  final committed = Completer<void>();
  int commits = 0;
  bool failRead = false;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    final result = await inner.transaction(action, exclusive: exclusive);
    commits++;
    if (commits == failAfterCommit) failRead = true;
    if (!committed.isCompleted) committed.complete();
    if (releaseCommit != null) await releaseCommit!.future;
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) {
    if (failRead &&
        table == "tracks" &&
        (where?.startsWith("id IN") ?? false)) {
      failRead = false;
      return Future.error(Exception("模拟提交成功后的列表读取失败"));
    }
    return inner.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      inner.rawQuery(sql, arguments);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<ProviderContainer> _open(WidgetTester tester,
    {bool desktop = false, bool play = false}) async {
  if (desktop) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final app = await buildTestApp(
      platform: desktop ? AppPlatform.windows : AppPlatform.android,
      seedTracks: const [
        {"id": "a", "name": "001 周杰伦 东方破", "author": "上传者"},
        {"id": "b", "name": "002 周杰伦 发如雪", "author": "上传者"},
      ]);
  final playlist = await PlaylistRepository().create("评审复现");
  await PlaylistRepository().addTrack(playlist.id, "a");
  await PlaylistRepository().addTrack(playlist.id, "b");
  await tester.pumpWidget(app);
  await _frames(tester);
  final container = ProviderScope.containerOf(
      tester.element(find.byType(PlaylistTile).first));
  if (play) {
    final tracks = await PlaylistRepository().items(playlist.id);
    container.read(playbackProvider.notifier).play(tracks.first, queue: tracks);
    await _frames(tester);
  }
  await tester.tap(find.descendant(
      of: find.byType(PlaylistTile).first, matching: find.text("评审复现")));
  await _frames(tester);
  await tester.tap(find.byKey(const Key("custom_playlist_more")));
  await _frames(tester);
  await tester.tap(find.text("批量重命名"));
  await _frames(tester);
  return container;
}

Future<void> _close(WidgetTester tester, Database original) async {
  appDb = original;
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await original.close();
}

Future<Map<String, Object?>> _row(Database db, String id) async =>
    (await db.query("tracks", where: "id = ?", whereArgs: [id])).single;

Future<void> _tapUndo(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key("rename_undo")));
  await tester.pump();
  await tester.tap(find.byKey(const Key("rename_undo")));
  await _frames(tester);
}

Future<void> _retryRefresh(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key("rename_retry_refresh")));
  await tester.pump();
  await tester.tap(find.byKey(const Key("rename_retry_refresh")));
  await _frames(tester);
}

void main() {
  testWidgets("提交后读取失败仍显示已保存，单独重试刷新不重复写库", (tester) async {
    final container = await _open(tester, play: true);
    final original = appDb;
    final probe = _DatabaseProbe(original, failAfterCommit: 1);
    appDb = probe;
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await _row(original, "a"))["display_name"], "东方破");
    expect(find.text("本次修改已保存"), findsOneWidget);
    expect(find.text("保存失败，本批修改未应用，请重试"), findsNothing);
    expect(find.byKey(const Key("rename_undo")), findsOneWidget);
    expect(probe.commits, 1);
    await _retryRefresh(tester);
    expect(find.byKey(const Key("rename_retry_refresh")), findsNothing);
    expect(container.read(playbackProvider).track!.effectiveName, "东方破");
    expect(probe.commits, 1);
    await _tapUndo(tester);
    expect((await _row(original, "a"))["display_name"], isNull);
    expect(find.byKey(const Key("rename_undo")), findsNothing);
    expect(probe.commits, 2);
    expect(tester.takeException(), isNull);
    await _close(tester, original);
  });

  testWidgets("撤销提交后读取失败也清除旧撤销操作，可重试刷新并再次应用", (tester) async {
    final container = await _open(tester, play: true);
    final original = appDb;
    final probe = _DatabaseProbe(original, failAfterCommit: 2);
    appDb = probe;
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    await _tapUndo(tester);
    expect((await _row(original, "a"))["display_name"], isNull);
    expect(find.byKey(const Key("rename_undo")), findsNothing);
    expect(find.text("修改已撤销，界面刷新失败，可重试刷新"), findsOneWidget);
    expect(probe.commits, 2);
    await _retryRefresh(tester);
    expect(
        container.read(playbackProvider).track!.effectiveName, "001 周杰伦 东方破");
    expect(probe.commits, 2);
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await _row(original, "a"))["display_name"], "东方破");
    expect(probe.commits, 3);
    expect(find.text("歌曲又被编辑过，无法撤销，请重新查看歌曲信息"), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester, original);
  });

  testWidgets("真正的事务冲突不显示保存成功，也不生成撤销操作", (tester) async {
    await _open(tester);
    final original = appDb;
    final probe = _DatabaseProbe(original);
    appDb = probe;
    await original.update("tracks", {"display_name": "较新的修改"},
        where: "id = ?", whereArgs: ["b"]);
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await _row(original, "a"))["display_name"], isNull);
    expect((await _row(original, "b"))["display_name"], "较新的修改");
    expect(find.text("歌曲信息已变化，请重新打开预览"), findsOneWidget);
    expect(find.byKey(const Key("rename_undo")), findsNothing);
    expect(find.byKey(const Key("rename_retry_refresh")), findsNothing);
    expect(probe.commits, 0);
    expect(tester.takeException(), isNull);
    await _close(tester, original);
  });

  for (final undo in [false, true]) {
    testWidgets("Windows ${undo ? "撤销" : "保存"}中切换侧栏仍完成播放器及列表同步",
        (tester) async {
      final container = await _open(tester, desktop: true, play: true);
      final playlistId = (await PlaylistRepository().list()).single.id;
      final details = container.listen(
          playlistDetailTracksProvider(playlistId), (previous, next) {});
      await _frames(tester);
      if (undo) {
        await tester.tap(find.byKey(const Key("rename_apply")));
        await _frames(tester);
      }
      final original = appDb;
      final release = Completer<void>();
      final probe = _DatabaseProbe(original, releaseCommit: release);
      appDb = probe;
      if (undo) {
        await _tapUndo(tester);
      } else {
        await tester.tap(find.byKey(const Key("rename_apply")));
        await _frames(tester);
      }
      expect(probe.committed.isCompleted, isTrue);
      await tester.tap(find.byKey(const ValueKey("desktop_nav_settings")));
      await _frames(tester);
      expect(find.byType(BatchRenamePage), findsNothing);
      release.complete();
      await _frames(tester);
      expect(
          (await _row(original, "a"))["display_name"], undo ? isNull : "东方破");
      expect(container.read(playbackProvider).track!.effectiveName,
          undo ? "001 周杰伦 东方破" : "东方破");
      expect(container.read(playbackProvider).queue.last.effectiveName,
          undo ? "002 周杰伦 发如雪" : "发如雪");
      final storedDetails =
          await container.read(playlistDetailTracksProvider(playlistId).future);
      expect(storedDetails.first.effectiveName, undo ? "001 周杰伦 东方破" : "东方破");
      expect(fakePlaybackEngine!.loads.length, 1);
      expect(tester.takeException(), isNull);
      details.close();
      await _close(tester, original);
    });
  }
}
