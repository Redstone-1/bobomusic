import "package:sqflite/sqflite.dart";

import "../db/app_database.dart";

import "../models/playlist.dart";
import "../models/track.dart";

/// 歌单仓库（§3.2）：歌单元数据 + 成员关系（普通歌单禁止重复，§3.4-6）
class PlaylistRepository {
  // 数据库直连全局实例（测试重指内存库）
  final Database db = appDb;

  PlaylistRepository();

  Playlist _fromRow(Map<String, Object?> row) => Playlist(
        id: "${row["id"]}",
        name: row["name"] as String,
        type: PlaylistType.values.byName(row["type"] as String),
        count: (row["track_count"] as int?) ?? 0,
      );

  /// 新建歌单（名称唯一，重复抛异常由 UI 提示）；返回带 id 的歌单
  Future<Playlist> create(String name,
      {PlaylistType type = PlaylistType.custom}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // sort_index 追加到末尾
    final maxRow = await db.query(
      "playlists",
      columns: ["MAX(sort_index) AS m"],
    );
    final nextIndex = ((maxRow.first["m"] as int?) ?? -1) + 1;
    final id = await db.insert("playlists", {
      "name": name,
      "type": type.name,
      "sort_index": nextIndex,
      "created_at": now,
    });
    return Playlist(id: "$id", name: name, type: type, count: 0);
  }

  Future<void> rename(int id, String name) async {
    await db.update(
      "playlists",
      {"name": name},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  /// 删除歌单（成员关系级联，曲目本体保留）
  Future<void> delete(int id) async =>
      db.delete("playlists", where: "id = ?", whereArgs: [id]);

  /// 歌单目录（含曲目计数）
  Future<List<Playlist>> list() async {
    final rows = await db.rawQuery("""
      SELECT p.*, (
        SELECT COUNT(*) FROM playlist_items i WHERE i.playlist_id = p.id
      ) AS track_count
      FROM playlists p
      ORDER BY p.sort_index, p.created_at
    """);
    return [for (final r in rows) _fromRow(r)];
  }

  /// 歌单内曲目（按成员排序）
  Future<List<Track>> items(String playlistId) async {
    final rows = await db.rawQuery("""
      SELECT t.*, i.sort_index AS item_sort
      FROM tracks t
      JOIN playlist_items i ON i.track_id = t.id
      WHERE i.playlist_id = ?
      ORDER BY i.sort_index
    """, [int.parse(playlistId)]);
    return [
      for (final r in rows)
        Track(
          id: r["id"] as String,
          name: r["name"] as String,
          author: (r["author"] ?? "") as String,
          cover: r["cover"] as String?,
          duration: r["duration"] as int?,
          origin: OriginType.values.byName(r["origin"] as String),
          liked: r["liked_at"] != null,
          localPath: r["local_path"] as String?,
          lyric: r["lyric"] as String?,
          lyricOffsetMs: (r["lyric_offset"] as int?) ?? 0,
        ),
    ];
  }

  /// 加入歌单；重复加入返回 false（§3.4-6：UNIQUE + 提示「已在歌单中」）
  Future<bool> addTrack(String playlistId, String trackId) async {
    try {
      final pid = int.parse(playlistId);
      final maxRow = await db.query(
        "playlist_items",
        columns: ["MAX(sort_index) AS m"],
        where: "playlist_id = ?",
        whereArgs: [pid],
      );
      final nextIndex = ((maxRow.first["m"] as int?) ?? -1) + 1;
      await db.insert("playlist_items", {
        "playlist_id": pid,
        "track_id": trackId,
        "sort_index": nextIndex,
        "added_at": DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return false;
      rethrow;
    }
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    await db.delete(
      "playlist_items",
      where: "playlist_id = ? AND track_id = ?",
      whereArgs: [int.parse(playlistId), trackId],
    );
  }

  /// 调序：按传入顺序重写 sort_index（事务）
  Future<void> reorder(String playlistId, List<String> orderedTrackIds) async {
    final pid = int.parse(playlistId);
    await db.transaction((txn) async {
      for (final (i, tid) in orderedTrackIds.indexed) {
        await txn.update(
          "playlist_items",
          {"sort_index": i},
          where: "playlist_id = ? AND track_id = ?",
          whereArgs: [pid, tid],
        );
      }
    });
  }
}
