import "dart:io";
import "dart:ui" as ui;

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/playlist_cover_store.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test("本地图复制后独立可用，删除歌单后歌曲仍引用的图片保留", () async {
    final root = await Directory.systemTemp.createTemp("bobo_cover_");
    await initAppDatabase(path: inMemoryDatabasePath);
    addTearDown(() async {
      await appDb.close();
      await root.delete(recursive: true);
    });
    final source = File("${root.path}/source.png");
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await source.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    final store = PlaylistCoverStore(
        directory: () async => Directory("${root.path}/managed"));
    final cover = await store.importFile(source);
    final file = File.fromUri(Uri.parse(cover));
    await source.delete();
    expect(await file.exists(), isTrue);
    await TrackRepository()
        .upsert(const Track(id: "a", name: "歌曲", author: ""));
    final p = await PlaylistRepository().create("歌单");
    await PlaylistRepository().addTrack(p.id, "a");
    await PlaylistRepository().updateInfo(p.id,
        name: "歌单", customCover: cover, applyCoverToTracks: true);
    await PlaylistRepository().delete(int.parse(p.id));
    await store.removeIfUnused(cover);
    expect(await file.exists(), isTrue);
    await TrackRepository().updateDisplayInfo("a", cover: "");
    await store.removeIfUnused(cover);
    expect(await file.exists(), isFalse);
  });

  test("损坏图片拒绝导入，目录外文件不会被清理", () async {
    final root = await Directory.systemTemp.createTemp("bobo_bad_cover_");
    addTearDown(() => root.delete(recursive: true));
    final source = await File("${root.path}/outside.jpg").writeAsString("不是图片");
    final store = PlaylistCoverStore(
        directory: () async => Directory("${root.path}/managed"));
    await expectLater(store.importFile(source), throwsA(anything));
    await store.removeIfUnused(source.uri.toString());
    expect(await source.exists(), isTrue);
  });
}
