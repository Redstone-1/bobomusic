import "package:sqflite/sqflite.dart";

/// v3 四表 schema（重构计划 §3.1）：tracks / playlists / playlist_items / queue
/// 全参数化 SQL；旧库迁移（批次 B）在首启检测时单独处理，与本库隔离

/// 全局数据库实例（main() 初始化；测试重指内存库）
late Database appDb;

/// 打开数据库；[path] 传 inMemoryDatabasePath 供单测使用
/// singleInstance 关闭：单测逐用例重开内存库时必须拿到全新实例
Future<void> initAppDatabase({String? path}) async {
  appDb = await openDatabase(
    path ?? "bobomusic3.db",
    version: 2,
    singleInstance: false,
    onConfigure: (db) async {
      // 级联删除依赖外键开关（sqflite 默认关闭）
      await db.execute("PRAGMA foreign_keys = ON");
    },
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );
}

/// v1 → v2：歌词时间校准偏移（S4.4 手动校准需要跨启动保留）
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute(
      "ALTER TABLE tracks ADD COLUMN lyric_offset INTEGER NOT NULL DEFAULT 0",
    );
  }
}

Future<void> _onCreate(Database db, int _) async {
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
  await db.execute("""
    CREATE TABLE queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      added_at INTEGER NOT NULL
    )
  """);
}
