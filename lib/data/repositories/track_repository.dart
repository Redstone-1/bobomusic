import "package:sqflite/sqflite.dart";

import "../db/app_database.dart";

import "../models/track.dart";

/// 曲目实体仓库（§3.2）：曲目 CRUD / 喜欢 / 歌词 / 下载登记
/// 读返回 UI 形状的 [Track]（liked = liked_at 非空）；upsert 保留 liked/downloaded/created
class TrackRepository {
  // 数据库直连全局实例（测试重指内存库）
  final Database db = appDb;

  TrackRepository();

  Track _fromRow(Map<String, Object?> row) => Track(
        id: row["id"] as String,
        name: row["name"] as String,
        author: (row["author"] ?? "") as String,
        cover: row["cover"] as String?,
        duration: row["duration"] as int?,
        origin: OriginType.values.byName(row["origin"] as String),
        liked: row["liked_at"] != null,
        localPath: row["local_path"] as String?,
        lyric: row["lyric"] as String?,
      );

  /// 插入或更新：新曲全字段写入；已存在只更新内容字段
  /// （liked_at/downloaded_at/created_at 永不被 upsert 覆盖）
  Future<void> upsert(Track track) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final content = {
      "name": track.name,
      "author": track.author,
      "cover": track.cover,
      "duration": track.duration ?? 0,
      "origin": track.origin.name,
      "updated_at": now,
    };
    // INSERT OR IGNORE：命中已存在则不动，随后仅更新内容
    final inserted = await db.insert(
      "tracks",
      {
        "id": track.id,
        ...content,
        "local_path": track.localPath,
        "lyric": track.lyric,
        "created_at": now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted == 0) {
      await db
          .update("tracks", content, where: "id = ?", whereArgs: [track.id]);
    }
  }

  Future<Track?> getById(String id) async {
    final rows = await db.query("tracks", where: "id = ?", whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// 本地音乐曲目（origin = local，倒序；本地扫描来源，排除下载目录由扫描器负责）
  Future<List<Track>> localTracks() async {
    final rows = await db.query(
      "tracks",
      where: "origin = ?",
      whereArgs: [OriginType.local.name],
      orderBy: "created_at DESC",
    );
    return [for (final r in rows) _fromRow(r)];
  }

  /// 本地音乐计数（歌单页快捷卡）
  Future<int> localCount() async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM tracks WHERE origin = ?",
      [OriginType.local.name],
    );
    return (rows.first["c"] as int?) ?? 0;
  }

  /// 全部曲目（本地音乐列表等）
  Future<List<Track>> getAll() async {
    final rows = await db.query("tracks", orderBy: "created_at DESC");
    return [for (final r in rows) _fromRow(r)];
  }

  /// 我喜欢（虚拟列表：liked_at 非空，倒序 = 最喜欢在前，§3.1）
  Future<List<Track>> likedTracks() async {
    final rows = await db.query(
      "tracks",
      where: "liked_at IS NOT NULL",
      orderBy: "liked_at DESC",
    );
    return [for (final r in rows) _fromRow(r)];
  }

  /// 全局喜欢开关（§3.4-2：一次点击，所有列表同步）
  Future<void> setLiked(String id, bool liked) async {
    await db.update(
      "tracks",
      {"liked_at": liked ? DateTime.now().millisecondsSinceEpoch : null},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<void> updateLyric(String id, String lyric) async {
    await db.update(
      "tracks",
      {"lyric": lyric, "updated_at": DateTime.now().millisecondsSinceEpoch},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  /// 下载登记（§3.4-8：localPath 登记到原 track，同身份可离线）
  Future<void> markDownloaded(String id, String localPath) async {
    await db.update(
      "tracks",
      {
        "local_path": localPath,
        "downloaded_at": DateTime.now().millisecondsSinceEpoch,
      },
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async =>
      db.delete("tracks", where: "id = ?", whereArgs: [id]);
}
