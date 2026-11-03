import "dart:io";

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/db/windows_database_path.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() {
  late Directory root;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp("bobo_windows_db");
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> prepare(List<String> legacyPaths) => prepareWindowsDatabase(
        supportDirectory: Directory(p.join(root.path, "support")),
        legacyPaths: legacyPaths,
        factory: databaseFactory,
      );

  test("首次启动使用固定支持目录，目标已存在时不处理其它旧库", () async {
    final target = await prepare([]);
    expect(target,
        p.join(root.path, "support", "databases", windowsDatabaseFileName));
    await File(target).writeAsString("existing");
    final invalid = File(p.join(root.path, "invalid.db"));
    await invalid.writeAsString("invalid");
    expect(await prepare([invalid.path]), target);
    expect(await File(target).readAsString(), "existing");
  });

  test("迁移包含 WAL 中的喜欢、歌词和歌单，保留旧库且再次启动不覆盖", () async {
    final legacy = p.join(root.path, "旧目录 ' 空格.db");
    await initAppDatabase(path: legacy);
    await appDb.rawQuery("PRAGMA journal_mode = WAL");
    await appDb.rawQuery("PRAGMA wal_autocheckpoint = 0");
    await TrackRepository().upsert(const Track(
        id: "t1", name: "保留曲目", author: "歌手", origin: OriginType.kuwo));
    await TrackRepository().setLiked("t1", true);
    await TrackRepository().updateLyric("t1", "[00:01.00]保留歌词", offsetMs: 500);
    final playlist = await appDb.insert(
        "playlists", {"name": "保留歌单", "type": "custom", "created_at": 1});
    await appDb.insert("playlist_items", {
      "playlist_id": playlist,
      "track_id": "t1",
      "sort_index": 0,
      "added_at": 1
    });
    final original = appDb;
    try {
      final target = await prepare([legacy]);
      expect(await File(legacy).exists(), isTrue);
      final snapshot = await databaseFactory.openDatabase(target,
          options: OpenDatabaseOptions(singleInstance: false));
      try {
        final row = (await snapshot.query("tracks")).single;
        expect(row["liked_at"], isNotNull);
        expect(row["lyric"], contains("保留歌词"));
        expect(row["lyric_offset"], 500);
        expect((await snapshot.query("playlist_items")).length, 1);
      } finally {
        await snapshot.close();
      }
      await original.update("tracks", {"name": "旧库后续改动"});
      expect(await prepare([legacy]), target);
      final check = await databaseFactory.openDatabase(target,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      try {
        expect((await check.query("tracks")).single["name"], "保留曲目");
      } finally {
        await check.close();
      }
    } finally {
      await original.close();
    }
  });

  test("损坏旧库迁移失败，不创建空目标且保留原文件", () async {
    final legacy = File(p.join(root.path, "broken.db"));
    await legacy.writeAsString("不是数据库");
    await expectLater(
        prepare([legacy.path]), throwsA(isA<FileSystemException>()));
    expect(await legacy.readAsString(), "不是数据库");
    expect(
        await File(p.join(
                root.path, "support", "databases", windowsDatabaseFileName))
            .exists(),
        isFalse);
  });

  test("多份旧库不猜测用户希望保留的数据", () async {
    final a = File(p.join(root.path, "a.db"));
    final b = File(p.join(root.path, "b.db"));
    await a.writeAsString("a");
    await b.writeAsString("b");
    await expectLater(
        prepare([a.path, b.path]), throwsA(isA<FileSystemException>()));
  });
}
