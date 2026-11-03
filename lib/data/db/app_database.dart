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
    version: 6,
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
/// v2 → v3：播放历史（歌单页「最近播放」，track_id 主键保证同曲只留最新一条）
/// v3 → v4：清除收藏合集歌单（功能已删除，playlist_items 由外键级联清理）
/// v4 → v5：曲目显示用歌名/歌手覆盖（B 站等音源标题可编辑，null = 未改）
/// v5 → v6：曲目显示用封面覆盖（可编辑封面 URL，null = 未改，原始 cover 保留）
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute(
      "ALTER TABLE tracks ADD COLUMN lyric_offset INTEGER NOT NULL DEFAULT 0",
    );
  }
  if (oldVersion < 3) {
    await db.execute("""
      CREATE TABLE play_history (
        track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
        played_at INTEGER NOT NULL
      )
    """);
  }
  if (oldVersion < 4) {
    await db.execute(
      "DELETE FROM playlists WHERE type = ?",
      ["collection"],
    );
  }
  if (oldVersion < 5) {
    await db.execute("ALTER TABLE tracks ADD COLUMN display_name TEXT");
    await db.execute("ALTER TABLE tracks ADD COLUMN display_author TEXT");
  }
  if (oldVersion < 6) {
    await db.execute("ALTER TABLE tracks ADD COLUMN display_cover TEXT");
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
      display_name TEXT,
      display_author TEXT,
      display_cover TEXT,
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
  await db.execute("""
    CREATE TABLE play_history (
      track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
      played_at INTEGER NOT NULL
    )
  """);
}
