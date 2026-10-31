import "dart:io";

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

/// v3 → v4 升级迁移：清除收藏合集歌单（功能已删除，条目随外键级联清理），
/// 自定义歌单及其曲目不受影响
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
}
