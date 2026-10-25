import "package:sqflite/sqflite.dart";

import "../db/app_database.dart";

import "../models/track.dart";

/// 播放队列仓库（§3.4-5）：独立于歌单、允许重复、跨启动持久化
/// 「下一首播放」= insertNext（插到队首偏移位）；「稍后听」= append
class QueueRepository {
  // 数据库直连全局实例（测试重指内存库）
  final Database db = appDb;

  QueueRepository();

  Track _fromRow(Map<String, Object?> r) => Track(
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
      );

  /// 队列全部曲目（按 position）
  Future<List<Track>> all() async {
    final rows = await db.rawQuery("""
      SELECT t.*, q.position
      FROM queue q
      JOIN tracks t ON t.id = q.track_id
      ORDER BY q.position
    """);
    return [for (final r in rows) _fromRow(r)];
  }

  /// 取出并移除队首（播放内核「插队优先」消费，事务内完成避免并发重复取）
  Future<Track?> takeFirst() async {
    return db.transaction((txn) async {
      final rows = await txn.rawQuery("""
        SELECT t.*, q.position AS queue_position
        FROM queue q
        JOIN tracks t ON t.id = q.track_id
        ORDER BY q.position
        LIMIT 1
      """);
      if (rows.isEmpty) return null;
      final position = rows.first["queue_position"] as int;
      await txn.delete("queue", where: "position = ?", whereArgs: [position]);
      await txn.execute(
        "UPDATE queue SET position = position - 1 WHERE position > ?",
        [position],
      );
      return _fromRow(rows.first);
    });
  }

  /// 整表替换（S4 播放会话装载队列用）
  Future<void> replaceAll(List<String> trackIds) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete("queue");
      for (final (i, tid) in trackIds.indexed) {
        await txn.insert("queue", {
          "track_id": tid,
          "position": i,
          "added_at": now,
        });
      }
    });
  }

  Future<void> append(String trackId) async {
    final maxRow = await db.query("queue", columns: ["MAX(position) AS m"]);
    final next = ((maxRow.first["m"] as int?) ?? -1) + 1;
    await _insertAt(trackId, next);
  }

  /// 下一首播放：插到 [atPosition]（当前曲之后），后续顺移
  Future<void> insertNext(String trackId, {int atPosition = 0}) async {
    await _insertAt(trackId, atPosition);
  }

  Future<void> _insertAt(String trackId, int position) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      // 顺移：腾出目标位
      await txn.execute(
        "UPDATE queue SET position = position + 1 WHERE position >= ?",
        [position],
      );
      await txn.insert("queue", {
        "track_id": trackId,
        "position": position,
        "added_at": now,
      });
    });
  }

  /// 移除某曲目的一次出现（队列允许重复，按 position 定位）
  Future<void> removeAt(int position) async {
    await db.transaction((txn) async {
      await txn.delete("queue", where: "position = ?", whereArgs: [position]);
      await txn.execute(
        "UPDATE queue SET position = position - 1 WHERE position > ?",
        [position],
      );
    });
  }

  /// 调序：把 from 位移动到 to 位，区间顺移
  Future<void> move(int from, int to) async {
    if (from == to) return;
    await db.transaction((txn) async {
      // 先记下被移动行的主键：顺移后旧 position 会易主，不能按 position 更新
      final moving = await txn.query(
        "queue",
        columns: ["id"],
        where: "position = ?",
        whereArgs: [from],
      );
      if (moving.isEmpty) return;
      final rowId = moving.first["id"] as int;
      if (from < to) {
        await txn.execute(
          "UPDATE queue SET position = position - 1 WHERE position > ? AND position <= ?",
          [from, to],
        );
      } else {
        await txn.execute(
          "UPDATE queue SET position = position + 1 WHERE position >= ? AND position < ?",
          [to, from],
        );
      }
      await txn.update("queue", {"position": to},
          where: "id = ?", whereArgs: [rowId]);
    });
  }

  Future<void> clear() async => db.delete("queue");
}
