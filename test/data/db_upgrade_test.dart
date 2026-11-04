import "dart:io";

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/history_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

Future<void> _createLegacyPlaylists(Database db) => db.execute("""
  CREATE TABLE playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,
    sort_index INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
""");

/// v3 → v4 升级迁移：清除收藏合集歌单（功能已删除，条目随外键级联清理），
/// 自定义歌单及其曲目不受影响
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test("v6 升级 v7 完整保留五表数据、顺序、唯一性及外键级联", () async {
    final dir = await Directory.systemTemp.createTemp("bobomusic_upgrade7");
    final dbPath = "${dir.path}/upgrade.db";
    addTearDown(() async {
      await appDb.close();
      await dir.delete(recursive: true);
    });
    await initAppDatabase(path: dbPath);
    await TrackRepository().upsert(const Track(
        id: "a",
        name: "原名",
        author: "原歌手",
        duration: 210,
        cover: "https://origin/a.jpg",
        lyric: "原歌词"));
    await TrackRepository().upsert(const Track(
        id: "b",
        name: "本地歌曲",
        author: "本地歌手",
        origin: OriginType.local,
        duration: 180,
        localPath: "local/b.mp3",
        lyric: "本地歌词"));
    await TrackRepository().setLiked("a", true);
    await TrackRepository().markDownloaded("a", "downloads/a.m4a");
    await TrackRepository().updateLyricOffset("a", 1250);
    await TrackRepository().updateDisplayInfo("a",
        name: "自定义名", author: "自定义歌手", cover: "https://old/a.jpg");
    final p = await PlaylistRepository().create("旧歌单");
    final second = await PlaylistRepository().create("另一歌单");
    await PlaylistRepository().addTrack(p.id, "b");
    await PlaylistRepository().addTrack(p.id, "a");
    await PlaylistRepository().addTrack(second.id, "a");
    await QueueRepository().replaceAll(["a", "b", "a"]);
    await HistoryRepository().record("a", at: DateTime.utc(2025, 1, 1));
    await HistoryRepository().record("b", at: DateTime.utc(2025, 1, 2));
    // 回到真实 v6 的列形状及版本，再使用应用入口验证升级。
    await appDb.execute("ALTER TABLE playlists DROP COLUMN custom_cover");
    await appDb.setVersion(6);
    // 比较所有旧字段，避免只检查显示名而遗漏喜欢、下载、歌词、条目主键或顺序。
    final before = <String, List<Map<String, Object?>>>{};
    const tables = {
      "tracks": "id",
      "playlists": "id",
      "playlist_items": "id",
      "queue": "id",
      "play_history": "track_id"
    };
    for (final entry in tables.entries) {
      before[entry.key] = await appDb.query(entry.key, orderBy: entry.value);
    }
    await appDb.close();
    await initAppDatabase(path: dbPath);
    expect(await appDb.getVersion(), 7);
    for (final entry in tables.entries) {
      final expected = [
        for (final row in before[entry.key]!)
          {...row, if (entry.key == "playlists") "custom_cover": null}
      ];
      expect(await appDb.query(entry.key, orderBy: entry.value), expected,
          reason: "${entry.key} 迁移后旧数据必须完整");
    }
    expect(
        (await appDb.rawQuery("PRAGMA foreign_keys")).single.values.single, 1);
    expect(await appDb.rawQuery("PRAGMA foreign_key_check"), isEmpty);
    expect((await PlaylistRepository().getById(p.id))!.customCover, isNull);
    expect(
        (await PlaylistRepository().items(p.id)).map((t) => t.id), ["b", "a"]);
    final track = (await TrackRepository().getById("a"))!;
    expect(track.effectiveName, "自定义名");
    expect(track.effectiveAuthor, "自定义歌手");
    expect(track.lyricOffsetMs, 1250);
    expect(track.lyric, "原歌词");
    expect(track.localPath, "downloads/a.m4a");
    expect((await TrackRepository().likedTracks()).map((t) => t.id), ["a"]);
    expect(
        (await TrackRepository().downloadedTracks()).map((t) => t.id), ["a"]);
    expect((await QueueRepository().all()).map((t) => t.id), ["a", "b", "a"]);
    expect((await HistoryRepository().recent()).map((t) => t.id), ["b", "a"]);
    expect(
        (await PlaylistRepository().getById(p.id))!.cover, "https://old/a.jpg");
    await expectLater(
        PlaylistRepository().create("旧歌单"), throwsA(isA<DatabaseException>()));
    expect(await PlaylistRepository().addTrack(p.id, "a"), isFalse);
    await expectLater(PlaylistRepository().addTrack(p.id, "missing"),
        throwsA(isA<DatabaseException>()));
    await PlaylistRepository()
        .updateInfo(p.id, name: "旧歌单", customCover: "https://new/p.jpg");
    await appDb.close();
    await initAppDatabase(path: dbPath);
    expect(
        (await PlaylistRepository().getById(p.id))!.cover, "https://new/p.jpg");
    expect((await QueueRepository().all()).map((t) => t.id), ["a", "b", "a"]);
    await PlaylistRepository().delete(int.parse(second.id));
    expect(
        await appDb.query("playlist_items",
            where: "playlist_id = ?", whereArgs: [int.parse(second.id)]),
        isEmpty);
    expect(await TrackRepository().getById("a"), isNotNull);
    // ALTER TABLE 后仍保留曲目到成员、队列和历史三条级联关系。
    await appDb.delete("tracks", where: "id = ?", whereArgs: ["a"]);
    expect((await PlaylistRepository().items(p.id)).map((t) => t.id), ["b"]);
    expect((await QueueRepository().all()).map((t) => t.id), ["b"]);
    expect((await HistoryRepository().recent()).map((t) => t.id), ["b"]);
    expect(await appDb.rawQuery("PRAGMA foreign_key_check"), isEmpty);
  });

  test("v3 旧库升级 v4：collection 歌单及条目清除，custom 歌单保留", () async {
    final dir = await Directory.systemTemp.createTemp("bobomusic_upgrade");
    final dbPath = "${dir.path}/upgrade.db";
    // 先关全局库句柄再删目录（Windows 下打开中的文件不可删）
    addTearDown(() async {
      await appDb.close();
      await dir.delete(recursive: true);
    });

    // 手工搭一个 v3 形状旧库（迁移涉及的三表）
    final old = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute("""
            CREATE TABLE tracks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              cover TEXT,
              duration INTEGER NOT NULL DEFAULT 0,
              origin TEXT NOT NULL,
              local_path TEXT,
              lyric TEXT,
              lyric_offset INTEGER NOT NULL DEFAULT 0,
              liked_at INTEGER,
              downloaded_at INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          """);
          await db.execute("""
            CREATE TABLE playlists (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              sort_index INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL
            )
          """);
          await db.execute("""
            CREATE TABLE playlist_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
              track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
              sort_index INTEGER NOT NULL DEFAULT 0,
              added_at INTEGER NOT NULL,
              UNIQUE(playlist_id, track_id)
            )
          """);
        },
      ),
    );
    for (final id in ["t1", "t2"]) {
      await old.insert("tracks", {
        "id": id,
        "name": "曲$id",
        "origin": "bili",
        "created_at": 1,
        "updated_at": 1,
      });
    }
    final collectionId = await old.insert("playlists", {
      "name": "旧收藏合集",
      "type": "collection",
      "sort_index": 0,
      "created_at": 1,
    });
    final customId = await old.insert("playlists", {
      "name": "我的歌单",
      "type": "custom",
      "sort_index": 1,
      "created_at": 2,
    });
    await old.insert("playlist_items", {
      "playlist_id": collectionId,
      "track_id": "t1",
      "sort_index": 0,
      "added_at": 1,
    });
    await old.insert("playlist_items", {
      "playlist_id": customId,
      "track_id": "t2",
      "sort_index": 0,
      "added_at": 2,
    });
    await old.close();

    // 用应用入口重开 → 触发 v3→v4 升级清理
    await initAppDatabase(path: dbPath);

    final playlists = await appDb.query("playlists");
    expect(playlists.map((r) => r["name"]), ["我的歌单"]);
    final items = await appDb.query("playlist_items");
    expect(items.map((r) => r["track_id"]), ["t2"]);
  });

  test("v4 旧库升级 v5：新增 display 列，旧数据完整且覆盖可写", () async {
    final dir = await Directory.systemTemp.createTemp("bobomusic_upgrade5");
    final dbPath = "${dir.path}/upgrade5.db";
    addTearDown(() async {
      await appDb.close();
      await dir.delete(recursive: true);
    });

    // 手工搭一个 v4 形状旧库（无 display 列，tracks 表与 v3 形状相同）
    final old = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await _createLegacyPlaylists(db);
          await db.execute("""
            CREATE TABLE tracks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              cover TEXT,
              duration INTEGER NOT NULL DEFAULT 0,
              origin TEXT NOT NULL,
              local_path TEXT,
              lyric TEXT,
              lyric_offset INTEGER NOT NULL DEFAULT 0,
              liked_at INTEGER,
              downloaded_at INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          """);
        },
      ),
    );
    await old.insert("tracks", {
      "id": "t1",
      "name": "曲1",
      "origin": "bili",
      "created_at": 1,
      "updated_at": 1,
    });
    await old.close();

    // 用应用入口重开 → 触发 v4→v5 升级加列
    await initAppDatabase(path: dbPath);

    // 旧数据完整
    final stored = await TrackRepository().getById("t1");
    expect(stored!.name, "曲1");
    expect(stored.displayName, isNull);
    // v5 能力可用：写入显示覆盖并读回
    await TrackRepository().updateDisplayInfo("t1", name: "改后名");
    expect((await TrackRepository().getById("t1"))!.effectiveName, "改后名");
  });

  test("v5 旧库升级 v6：新增 display_cover 列，旧数据与封面覆盖可用", () async {
    final dir = await Directory.systemTemp.createTemp("bobomusic_upgrade6");
    final dbPath = "${dir.path}/upgrade6.db";
    addTearDown(() async {
      await appDb.close();
      await dir.delete(recursive: true);
    });

    // 手工搭一个 v5 形状旧库（有 display_name/display_author，无 display_cover）
    final old = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await _createLegacyPlaylists(db);
          await db.execute("""
            CREATE TABLE tracks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              cover TEXT,
              duration INTEGER NOT NULL DEFAULT 0,
              origin TEXT NOT NULL,
              local_path TEXT,
              lyric TEXT,
              lyric_offset INTEGER NOT NULL DEFAULT 0,
              display_name TEXT,
              display_author TEXT,
              liked_at INTEGER,
              downloaded_at INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          """);
        },
      ),
    );
    await old.insert("tracks", {
      "id": "t1",
      "name": "曲1",
      "cover": "https://original.example/c.jpg",
      "origin": "bili",
      "created_at": 1,
      "updated_at": 1,
    });
    await old.close();

    // 用应用入口重开 → 触发 v5→v6 升级加列
    await initAppDatabase(path: dbPath);

    // 旧数据完整（含原始封面）
    final stored = await TrackRepository().getById("t1");
    expect(stored!.name, "曲1");
    expect(stored.effectiveCover, "https://original.example/c.jpg");
    // v6 能力可用：写入封面覆盖并读回，原始 cover 保留
    await TrackRepository().updateDisplayInfo("t1", cover: "https://new.example/c.jpg");
    final edited = (await TrackRepository().getById("t1"))!;
    expect(edited.displayCover, "https://new.example/c.jpg");
    expect(edited.effectiveCover, "https://new.example/c.jpg");
  });
}
