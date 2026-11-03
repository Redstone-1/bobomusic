import "dart:io";

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/local_audio_scanner.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/playlist/local_scan_controller.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;
import "package:sqflite_common_ffi/sqflite_ffi.dart";

class _BrokenMetadata implements AudioMetadataSource {
  @override
  RawAudioMeta read(File file) => throw StateError("元数据损坏");
}

void main() {
  late Directory root;
  late TrackRepository repository;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await initAppDatabase(path: inMemoryDatabasePath);
    repository = TrackRepository();
    root = await Directory.systemTemp.createTemp("bobo_scoped_scan");
  });
  tearDown(() async {
    await appDb.close();
    await root.delete(recursive: true);
  });
  Track local(String id, String relative) => Track(
      id: id,
      name: id,
      author: "歌手",
      origin: OriginType.local,
      localPath: p.join(root.path, relative));

  test("完整扫描只清理范围内的缺失曲目，失败文件与其它目录保留", () async {
    for (final track in [
      local("missing", "a/missing.mp3"),
      local("broken", "a/broken.mp3"),
      local("outside", "b/keep.mp3")
    ]) {
      await repository.upsert(track);
    }
    await repository.setLiked("outside", true);
    await repository.updateLyric("outside", "保留歌词");
    await repository.syncLocalTracks([],
        scannedRoots: [p.join(root.path, "a")],
        retainedPaths: [p.join(root.path, "a/broken.mp3")]);
    expect(await repository.getById("missing"), isNull);
    expect(await repository.getById("broken"), isNotNull);
    expect((await repository.getById("outside"))?.liked, isTrue);
    expect((await repository.getById("outside"))?.lyric, "保留歌词");
  });

  test("离线目录进入扫描结果，控制器不删除原有曲目", () async {
    final path = p.join(root.path, "offline");
    await repository.upsert(local("offline", "offline/keep.mp3"));
    final controller = LocalScanController(
        taskFactory: () => LocalAudioScanner()
            .scanTask(roots: [Directory(path)], source: _BrokenMetadata()));
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.failures.single.path, path);
    expect(await repository.getById("offline"), isNotNull);
  });

  test("元数据失败不是删除文件，空结果也保留已有身份", () async {
    final file = File(p.join(root.path, "broken.mp3"));
    await file.writeAsString("broken");
    await repository.upsert(local("existing", "broken.mp3"));
    final controller = LocalScanController(
        taskFactory: () => LocalAudioScanner()
            .scanTask(roots: [root], source: _BrokenMetadata()));
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.failed, 1);
    expect(await repository.getById("existing"), isNotNull);
  });
}
