import "dart:io";
import "dart:async";
import "dart:ui" as ui;

import "package:bobomusic/core/platform/app_platform.dart";
import "package:bobomusic/core/widgets/app_checkbox_row.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track_display_edit.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/playlist/batch_track_edit_page.dart";
import "package:bobomusic/features/playlist/playlist_tile.dart";
import "package:bobomusic/core/widgets/cover_placeholder.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite/sqflite.dart";

import "../../helpers/app_test_helper.dart";

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

Finder _key(BatchTrackEditMode mode, String name) =>
    find.byKey(Key("batch_${mode.name}_$name"));

Future<ProviderContainer> _open(WidgetTester tester, BatchTrackEditMode mode,
    {bool desktop = false,
    bool play = false,
    String? secondCover,
    String initialCover = "https://old.test/a.jpg"}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize =
      desktop ? const Size(1440, 900) : const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final app = await buildTestApp(
      platform: desktop ? AppPlatform.windows : AppPlatform.android,
      prefs: {
        "theme_mode": desktop ? "dark" : "light"
      },
      seedTracks: const [
        {"id": "a", "name": "第一首", "author": "原歌手"},
        {"id": "b", "name": "第二首", "author": "原歌手"},
      ]);
  await TrackRepository().updateDisplayInfo("a",
      name: "手动歌名", author: "旧覆盖歌手", cover: initialCover);
  await TrackRepository().setLiked("a", true);
  if (secondCover != null) {
    await TrackRepository().updateDisplayBatch([
      TrackDisplayEdit(trackId: "b", cover: secondCover, updateCover: true),
    ]);
  }
  final playlist = await PlaylistRepository().create("批量字段测试");
  for (final id in ["a", "b"]) {
    await PlaylistRepository().addTrack(playlist.id, id);
  }
  await tester.pumpWidget(app);
  await _frames(tester);
  await tester.tap(find.descendant(
      of: find.byType(PlaylistTile).first, matching: find.text("批量字段测试")));
  await _frames(tester);
  await tester.tap(find.byKey(const Key("custom_playlist_more")));
  await _frames(tester);
  final renameY = tester.getCenter(find.text("批量重命名")).dy;
  final authorY = tester.getCenter(find.text("批量设置歌手")).dy;
  final coverY = tester.getCenter(find.text("批量设置封面")).dy;
  expect(authorY, greaterThan(renameY));
  expect(coverY, greaterThan(authorY));
  await tester.tap(find.text(mode.title));
  await _frames(tester);
  final container = ProviderScope.containerOf(
      tester.element(find.byType(BatchTrackEditPage)));
  if (play) {
    final queue = await PlaylistRepository().items(playlist.id);
    container.read(playbackProvider.notifier).play(queue.first, queue: queue);
    await _frames(tester);
    fakePlaybackEngine!.emitPosition(const Duration(seconds: 27));
    await tester.pump();
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
  return container;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _frames(tester);
}

Future<void> _enter(
    WidgetTester tester, BatchTrackEditMode mode, String value) async {
  await tester.ensureVisible(_key(mode, "value"));
  await tester.enterText(_key(mode, "value"), value);
  await _frames(tester);
}

class _ImagePicker extends FilePickerPlatform {
  _ImagePicker(this.source);
  final File source;

  @override
  Future<PlatformFile?> pickFile(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      int compressionQuality = 0,
      AndroidOptions androidOptions = const AndroidOptions(),
      DarwinOptions darwinOptions = const DarwinOptions(),
      WindowsOptions windowsOptions = const WindowsOptions(),
      LinuxOptions linuxOptions = const LinuxOptions(),
      WebOptions webOptions = const WebOptions()}) async {
    expect(type, FileType.image);
    return _PickedImage(source);
  }
}

final class _PickedImage extends PlatformFile {
  _PickedImage(this.source);
  final File source;
  @override
  String get name => "source.png";
  @override
  Uri get uri => source.uri;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoverFiles {
  _CoverFiles(this.root, this.source, this.old);
  final Directory root;
  final File source;
  final File old;

  static Future<_CoverFiles> create(WidgetTester tester) async {
    final files = (await tester.runAsync(() async {
      final root =
          await Directory.systemTemp.createTemp("bobo_cover_lifecycle_");
      final managed = await Directory("${root.path}/playlist_covers").create();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final source = await File("${root.path}/source.png")
          .writeAsBytes(bytes!.buffer.asUint8List());
      final old = await source.copy("${managed.path}/old.png");
      image.dispose();
      picture.dispose();
      return _CoverFiles(root, source, old);
    }))!;
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _ImagePicker(files.source);
    const channel = MethodChannel("plugins.flutter.io/path_provider");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => files.root.path);
    addTearDown(() async {
      FilePickerPlatform.instance = originalPicker;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await files.root.delete(recursive: true);
    });
    return files;
  }
}

Future<File> _pickLocalCover(WidgetTester tester) async {
  await tester.ensureVisible(_key(BatchTrackEditMode.cover, "pick_cover"));
  await tester.runAsync(() async {
    await tester.tap(_key(BatchTrackEditMode.cover, "pick_cover"));
    for (var frame = 0; frame < 60; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (find.text("已选择设备图片，填写链接可替换").evaluate().isNotEmpty) break;
    }
  });
  await _frames(tester);
  expect(find.text("已选择设备图片，填写链接可替换"), findsOneWidget);
  final preview = tester.widget<CoverPlaceholder>(find
      .descendant(
          of: find.byType(BatchTrackEditPage),
          matching: find.byType(CoverPlaceholder))
      .first);
  return File.fromUri(Uri.parse(preview.cover!));
}

Future<void> _flushFiles(WidgetTester tester, {bool Function()? done}) async {
  await tester.runAsync(() async {
    for (var frame = 0; frame < 60; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (done?.call() ?? frame >= 2) break;
    }
  });
}

/// 控制事务提交前或提交后的返回时机，复现写入仍在等待时被桌面侧栏移除。
class _CoverWriteGate implements Database {
  _CoverWriteGate(this.inner,
      {required this.afterCommit,
      this.failWrite = false,
      this.failRead = false});
  final Database inner;
  final bool afterCommit;
  final bool failWrite;
  final bool failRead;
  final reached = Completer<void>();
  final release = Completer<void>();
  bool _used = false;
  bool _readFailure = false;

  Future<void> _wait() async {
    reached.complete();
    await release.future;
    if (failWrite) throw StateError("模拟封面事务回滚");
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    if (_used) return inner.transaction(action, exclusive: exclusive);
    _used = true;
    final result = await inner.transaction((txn) async {
      final value = await action(txn);
      if (!afterCommit) await _wait();
      return value;
    }, exclusive: exclusive);
    if (afterCommit) await _wait();
    _readFailure = failRead;
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
    if (_readFailure &&
        table == "tracks" &&
        (where?.startsWith("id IN") ?? false)) {
      _readFailure = false;
      return Future.error(Exception("模拟封面写入成功后的刷新失败"));
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

Future<void> _coverWriteOnExit(WidgetTester tester,
    {required bool undo,
    required bool afterCommit,
    bool failWrite = false,
    bool failRead = false}) async {
  const mode = BatchTrackEditMode.cover;
  final files = await _CoverFiles.create(tester);
  final container = await _open(tester, mode,
      desktop: true, play: true, initialCover: files.old.uri.toString());
  final imported = await _pickLocalCover(tester);
  if (undo) {
    await _tap(tester, _key(mode, "apply"));
    await _flushFiles(tester);
    expect(await tester.runAsync(files.old.exists), isTrue,
        reason: "可撤销时旧图必须保留");
  }
  final originalDb = appDb;
  final gate = _CoverWriteGate(originalDb,
      afterCommit: afterCommit, failWrite: failWrite, failRead: failRead);
  appDb = gate;
  addTearDown(() async {
    if (!gate.release.isCompleted) gate.release.complete();
    appDb = originalDb;
    await _frames(tester);
    await _flushFiles(tester);
  });
  await _tap(tester, _key(mode, undo ? "undo" : "apply"));
  expect(gate.reached.isCompleted, isTrue);
  await _tap(tester, find.byKey(const ValueKey("desktop_nav_settings")));
  expect(find.byType(BatchTrackEditPage), findsNothing);
  await _flushFiles(tester);
  expect(await tester.runAsync(files.old.exists), isTrue,
      reason: "保存或撤销未收尾，不能清理旧图");
  expect(await tester.runAsync(imported.exists), isTrue,
      reason: "保存或撤销未收尾，不能清理新图");
  gate.release.complete();
  await _frames(tester);
  final restoreOld = undo != failWrite;
  await _flushFiles(tester,
      done: () =>
          restoreOld ? !imported.existsSync() : !files.old.existsSync());
  final stored = (await TrackRepository().getById("a"))!;
  expect(stored.effectiveCover,
      restoreOld ? files.old.uri.toString() : imported.uri.toString());
  expect(await tester.runAsync(files.old.exists), restoreOld);
  expect(await tester.runAsync(imported.exists), !restoreOld);
  expect(await tester.runAsync(files.source.exists), isTrue);
  if (!failRead) {
    expect(container.read(playbackProvider).track!.effectiveCover,
        stored.effectiveCover);
    expect(fakePlaybackEngine!.loads.length, 1);
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final mode in [BatchTrackEditMode.author, BatchTrackEditMode.cover]) {
    testWidgets("${mode.title}：已选同值项的后续变化也会阻止整批提交", (tester) async {
      const sameCover = "https://same.test/p.jpg";
      await _open(tester, mode,
          secondCover: mode == BatchTrackEditMode.cover ? sameCover : null);
      await _enter(
          tester, mode, mode == BatchTrackEditMode.author ? "原歌手" : sameCover);
      await TrackRepository().updateDisplayBatch([
        TrackDisplayEdit(
            trackId: "b",
            author: "后续歌手",
            cover: "https://later.test/p.jpg",
            updateAuthor: mode == BatchTrackEditMode.author,
            updateCover: mode == BatchTrackEditMode.cover),
      ]);
      await _tap(tester, _key(mode, "apply"));
      final stored = (await TrackRepository().getById("a"))!;
      expect(stored.displayAuthor, "旧覆盖歌手");
      expect(stored.displayCover, "https://old.test/a.jpg");
      expect(find.text("歌曲信息已变化，请重新打开预览"), findsOneWidget);
      expect(_key(mode, "undo"), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("${mode.title}：同值项仅校验，不写入、不计入成功数或撤销", (tester) async {
      const sameCover = "https://same.test/p.jpg";
      await _open(tester, mode,
          secondCover: mode == BatchTrackEditMode.cover ? sameCover : null);
      final before =
          (await appDb.query("tracks", where: "id = ?", whereArgs: ["b"]))
              .single;
      await _enter(
          tester, mode, mode == BatchTrackEditMode.author ? "原歌手" : sameCover);
      await _tap(tester, _key(mode, "apply"));
      expect(find.text("已更新 1 首歌曲"), findsOneWidget);
      expect(
          (await appDb.query("tracks", where: "id = ?", whereArgs: ["b"]))
              .single,
          before);
      await TrackRepository().updateDisplayBatch([
        TrackDisplayEdit(
            trackId: "b",
            author: "后续歌手",
            cover: "https://later.test/p.jpg",
            updateAuthor: mode == BatchTrackEditMode.author,
            updateCover: mode == BatchTrackEditMode.cover),
      ]);
      await _tap(tester, _key(mode, "undo"));
      final restored = (await TrackRepository().getById("a"))!;
      expect(restored.displayAuthor, "旧覆盖歌手");
      expect(restored.displayCover, "https://old.test/a.jpg");
      final skipped = (await TrackRepository().getById("b"))!;
      expect(
          mode == BatchTrackEditMode.author
              ? skipped.effectiveAuthor
              : skipped.effectiveCover,
          mode == BatchTrackEditMode.author
              ? "后续歌手"
              : "https://later.test/p.jpg");
      expect(tester.takeException(), isNull);
    });

    testWidgets("${mode.title}：横屏键盘不溢出，输入焦点保持且播放条随键盘恢复", (tester) async {
      await _open(tester, mode, play: true);
      await _enter(tester, mode,
          mode == BatchTrackEditMode.author ? "新歌手" : "https://new.test/p.jpg");
      final editable = tester.widget<EditableText>(find.descendant(
          of: _key(mode, "value"), matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key("mini_player")), findsNothing);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(_key(mode, "apply").hitTestable(), findsOneWidget);
      expect(
          tester.getRect(_key(mode, "apply")).bottom, lessThanOrEqualTo(140));
      await _enter(
          tester,
          mode,
          mode == BatchTrackEditMode.author
              ? "继续输入"
              : "https://input.test/p.jpg");
      tester.view.viewInsets = const FakeViewPadding();
      await _frames(tester);
      expect(find.byKey(const Key("mini_player")), findsOneWidget);
      expect(tester.getRect(_key(mode, "apply")).bottom,
          lessThan(tester.getRect(find.byKey(const Key("mini_player"))).top));
      expect(tester.takeException(), isNull);
    });

    for (final desktop in [false, true]) {
      testWidgets(
          "${mode.title} ${desktop ? "桌面暗色" : "手机亮色"}：默认全选、修改输入保留选择、预览零写入及字段级撤销",
          (tester) async {
        final container =
            await _open(tester, mode, desktop: desktop, play: true);
        final beforeA = (await TrackRepository().getById("a"))!;
        final beforeB = (await TrackRepository().getById("b"))!;
        final loads = fakePlaybackEngine!.loads.length;
        expect(
            tester.widget<FilledButton>(_key(mode, "apply")).onPressed, isNull);
        final value = mode == BatchTrackEditMode.author
            ? "新歌手"
            : "https://new.test/cover.jpg";
        await _enter(tester, mode, value);
        for (final id in ["a", "b"]) {
          expect(tester.widget<AppCheckboxRow>(_key(mode, "track_$id")).value,
              isTrue);
        }
        final input = tester.widget<TextField>(find.descendant(
            of: _key(mode, "value"), matching: find.byType(TextField)));
        expect(input.decoration!.filled, isTrue);
        expect(input.decoration!.enabledBorder, isA<OutlineInputBorder>());
        final secondBox = find.descendant(
            of: _key(mode, "track_b"), matching: find.byType(Checkbox));
        await _tap(tester, secondBox);
        await _enter(tester, mode, "  $value  ");
        expect(tester.widget<AppCheckboxRow>(_key(mode, "track_b")).value,
            isFalse);
        expect((await TrackRepository().getById("a"))!.displayAuthor,
            beforeA.displayAuthor);
        expect((await TrackRepository().getById("a"))!.displayCover,
            beforeA.displayCover);
        await _tap(tester, _key(mode, "apply"));
        final savedA = (await TrackRepository().getById("a"))!;
        final savedB = (await TrackRepository().getById("b"))!;
        expect(savedA.name, beforeA.name);
        expect(savedA.displayName, beforeA.displayName);
        expect(savedA.author, beforeA.author);
        expect(savedA.cover, beforeA.cover);
        expect(savedA.liked, isTrue);
        expect(savedB.displayAuthor, beforeB.displayAuthor);
        expect(savedB.displayCover, beforeB.displayCover);
        if (mode == BatchTrackEditMode.author) {
          expect(savedA.effectiveAuthor, value);
          expect(savedA.displayCover, beforeA.displayCover);
          expect(
              container.read(playbackProvider).track!.effectiveAuthor, value);
          await TrackRepository().updateDisplayBatch([
            const TrackDisplayEdit(
                trackId: "a",
                updateCover: true,
                cover: "https://later.test/a.jpg")
          ]);
        } else {
          expect(savedA.effectiveCover, value);
          expect(savedA.displayAuthor, beforeA.displayAuthor);
          expect(container.read(playbackProvider).track!.effectiveCover, value);
          await TrackRepository().updateDisplayBatch([
            const TrackDisplayEdit(
                trackId: "a", updateAuthor: true, author: "后续歌手编辑")
          ]);
        }
        expect(container.read(playbackProvider).position,
            const Duration(seconds: 27));
        expect(fakePlaybackEngine!.loads.length, loads);
        await _tap(tester, _key(mode, "undo"));
        final undone = (await TrackRepository().getById("a"))!;
        if (mode == BatchTrackEditMode.author) {
          expect(undone.displayAuthor, beforeA.displayAuthor);
          expect(undone.effectiveCover, "https://later.test/a.jpg");
        } else {
          expect(undone.displayCover, beforeA.displayCover);
          expect(undone.effectiveAuthor, "后续歌手编辑");
        }
        expect(fakePlaybackEngine!.loads.length, loads);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets("${mode.title}：空值或非法链接不能应用，全选/取消全选和返回不写库", (tester) async {
      await _open(tester, mode);
      await _enter(tester, mode,
          mode == BatchTrackEditMode.cover ? "file:///非法链接.png" : "   ");
      expect(
          tester.widget<FilledButton>(_key(mode, "apply")).onPressed, isNull);
      expect(
          find.text(mode == BatchTrackEditMode.cover
              ? "请填写有效的 http 或 https 图片链接，或从设备选择图片"
              : "请填写新的歌手名称"),
          findsOneWidget);
      await _enter(tester, mode,
          mode == BatchTrackEditMode.cover ? "https://new.test/p.jpg" : "新歌手");
      await _tap(tester, _key(mode, "select_none"));
      expect(
          tester.widget<FilledButton>(_key(mode, "apply")).onPressed, isNull);
      await _tap(tester, _key(mode, "select_all"));
      expect(tester.widget<FilledButton>(_key(mode, "apply")).onPressed,
          isNotNull);
      await _tap(tester, find.text("返回歌曲列表"));
      final stored = (await TrackRepository().getById("a"))!;
      expect(stored.displayAuthor, "旧覆盖歌手");
      expect(stored.displayCover, "https://old.test/a.jpg");
      expect(tester.takeException(), isNull);
    });

    testWidgets("${mode.title}：预览后的同字段编辑会阻止整批提交", (tester) async {
      await _open(tester, mode);
      await _enter(tester, mode,
          mode == BatchTrackEditMode.cover ? "https://new.test/p.jpg" : "新歌手");
      await TrackRepository().updateDisplayInfo("b",
          author: mode == BatchTrackEditMode.author ? "另一处歌手编辑" : null,
          cover: mode == BatchTrackEditMode.cover
              ? "https://later.test/b.jpg"
              : null);
      await _tap(tester, _key(mode, "apply"));
      final a = (await TrackRepository().getById("a"))!;
      expect(a.displayAuthor, "旧覆盖歌手");
      expect(a.displayCover, "https://old.test/a.jpg");
      expect(_key(mode, "undo"), findsNothing);
      expect(tester.widget<FilledButton>(_key(mode, "apply")).onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final undo in [false, true]) {
    for (final afterCommit in [false, true]) {
      testWidgets(
          "封面${undo ? "撤销" : "保存"}在${afterCommit ? "提交后" : "提交前"}离开页面，新旧文件保留到事务收尾",
          (tester) async {
        await _coverWriteOnExit(tester, undo: undo, afterCommit: afterCommit);
      });
    }
    testWidgets("封面${undo ? "撤销" : "保存"}中离开页面，事务回滚后只清理最终无引用的文件",
        (tester) async {
      await _coverWriteOnExit(tester,
          undo: undo, afterCommit: false, failWrite: true);
    });
    testWidgets("封面${undo ? "撤销" : "保存"}中离开页面，提交后刷新失败仍按真实数据库保全文件",
        (tester) async {
      await _coverWriteOnExit(tester,
          undo: undo, afterCommit: true, failRead: true);
    });

    testWidgets("受管旧封面在撤销机会结束前保留，${undo ? "撤销后" : "保存后"}正常退出按引用清理",
        (tester) async {
      const mode = BatchTrackEditMode.cover;
      final files = await _CoverFiles.create(tester);
      await _open(tester, mode, initialCover: files.old.uri.toString());
      final imported = await _pickLocalCover(tester);
      await _tap(tester, _key(mode, "apply"));
      await _flushFiles(tester);
      expect(await tester.runAsync(files.old.exists), isTrue);
      expect(await tester.runAsync(imported.exists), isTrue);
      if (undo) {
        await _tap(tester, _key(mode, "undo"));
        expect((await TrackRepository().getById("a"))!.effectiveCover,
            files.old.uri.toString());
      }
      await _tap(tester, find.text("返回歌曲列表"));
      await _flushFiles(tester,
          done: () => undo ? !imported.existsSync() : !files.old.existsSync());
      expect(await tester.runAsync(files.old.exists), undo);
      expect(await tester.runAsync(imported.exists), !undo);
      expect(await tester.runAsync(files.source.exists), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final playlistReference in [false, true]) {
    testWidgets("旧封面仍被其他${playlistReference ? "歌单" : "歌曲"}引用时，退出批量编辑也不能删除",
        (tester) async {
      const mode = BatchTrackEditMode.cover;
      final files = await _CoverFiles.create(tester);
      await _open(tester, mode, initialCover: files.old.uri.toString());
      if (playlistReference) {
        final other = await PlaylistRepository().create("继续使用旧图");
        await PlaylistRepository().updateInfo(other.id,
            name: other.name, customCover: files.old.uri.toString());
      } else {
        await TrackRepository()
            .upsert(const Track(id: "shared", name: "共享封面", author: "歌手"));
        await TrackRepository().updateDisplayBatch([
          TrackDisplayEdit(
              trackId: "shared",
              cover: files.old.uri.toString(),
              updateCover: true),
        ]);
      }
      final imported = await _pickLocalCover(tester);
      await _tap(tester, _key(mode, "apply"));
      await _tap(tester, find.text("返回歌曲列表"));
      await _flushFiles(tester);
      expect(
          await PlaylistRepository()
              .isCoverReferenced(files.old.uri.toString()),
          isTrue);
      expect(await tester.runAsync(files.old.exists), isTrue);
      expect(await tester.runAsync(imported.exists), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("选择新封面后取消，清理未保存的副本并保全旧图和设备源文件", (tester) async {
    const mode = BatchTrackEditMode.cover;
    final files = await _CoverFiles.create(tester);
    await _open(tester, mode, initialCover: files.old.uri.toString());
    final imported = await _pickLocalCover(tester);
    await _tap(tester, find.text("返回歌曲列表"));
    await _flushFiles(tester, done: () => !imported.existsSync());
    expect(await tester.runAsync(imported.exists), isFalse);
    expect(await tester.runAsync(files.old.exists), isTrue);
    expect(await tester.runAsync(files.source.exists), isTrue);
    expect((await TrackRepository().getById("a"))!.effectiveCover,
        files.old.uri.toString());
    expect(tester.takeException(), isNull);
  });

  testWidgets("设备封面复制后应用到歌曲，撤销后退出清理副本且保留源图片", (tester) async {
    const mode = BatchTrackEditMode.cover;
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp("bobo_batch_cover_")))!;
    final source = File("${root.path}/source.png");
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await source.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _ImagePicker(source);
    const pathChannel = MethodChannel("plugins.flutter.io/path_provider");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => root.path);
    addTearDown(() async {
      FilePickerPlatform.instance = originalPicker;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await root.delete(recursive: true);
    });
    await _open(tester, mode, initialCover: source.uri.toString());
    await tester.runAsync(() async {
      await tester.tap(_key(mode, "pick_cover"));
      for (var frame = 0; frame < 40; frame++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text("已选择设备图片，填写链接可替换").evaluate().isNotEmpty) break;
      }
    });
    await _frames(tester);
    expect(find.text("已选择设备图片，填写链接可替换"), findsOneWidget);
    await _tap(tester, _key(mode, "apply"));
    final cover = (await TrackRepository().getById("a"))!.effectiveCover!;
    final copy = File.fromUri(Uri.parse(cover));
    expect(copy.path, isNot(source.path));
    expect(await tester.runAsync(copy.exists), isTrue);
    expect((await TrackRepository().getById("b"))!.effectiveCover, cover);
    await _tap(tester, _key(mode, "undo"));
    await _tap(tester, find.text("返回歌曲列表"));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 40 && await copy.exists(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(await tester.runAsync(copy.exists), isFalse);
    expect(await tester.runAsync(source.exists), isTrue);
    expect(tester.takeException(), isNull);
  });
}
