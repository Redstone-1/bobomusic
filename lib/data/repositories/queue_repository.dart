import "package:sqflite/sqflite.dart";

import "../db/app_database.dart";

import "../models/track.dart";
import "../models/queue_entry.dart";

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
        displayName: r["display_name"] as String?,
        displayAuthor: r["display_author"] as String?,
      );

  QueueEntry _entryFromRow(Map<String, Object?> row) =>
      QueueEntry(id: row["queue_entry_id"] as int, track: _fromRow(row));

  /// 按位置读取独立排队记录，保留主键以避免重排后操作错位。
  Future<List<QueueEntry>> entries() async {
    final rows = await db.rawQuery("""
        SELECT t.*, q.id AS queue_entry_id
        FROM queue q
        JOIN tracks t ON t.id = q.track_id
        ORDER BY q.position
      """);
    return [for (final row in rows) _entryFromRow(row)];
  }

  Future<QueueEntry?> entryById(int entryId) async {
    final rows = await db.rawQuery(
      """
        SELECT t.*, q.id AS queue_entry_id
        FROM queue q
        JOIN tracks t ON t.id = q.track_id
        WHERE q.id = ?
      """,
      [entryId],
    );
    return rows.isEmpty ? null : _entryFromRow(rows.first);
  }

  /// 兼容只需要曲目的调用方，重复次数和顺序均保留。
  Future<List<Track>> all() async => [
    for (final entry in await entries()) entry.track,
  ];

  /// 按独立条目删除；迟到的菜单遇到已出队记录时不影响其它条目。
  Future<bool> removeEntry(int entryId) async {
    return db.transaction((txn) async {
      final rows = await txn.query(
        "queue",
        columns: ["position"],
        where: "id = ?",
        whereArgs: [entryId],
      );
      if (rows.isEmpty) return false;
      final position = rows.single["position"] as int;
      await txn.delete("queue", where: "id = ?", whereArgs: [entryId]);
      await txn.execute(
        "UPDATE queue SET position = position - 1 WHERE position > ?",
        [position],
      );
      return true;
    });
  }

  /// 把已有排队记录移到最前，不额外复制同曲条目。
  Future<bool> moveEntryToFront(int entryId) async {
    return db.transaction((txn) async {
      final rows = await txn.query(
        "queue",
        columns: ["position"],
        where: "id = ?",
        whereArgs: [entryId],
      );
      if (rows.isEmpty) return false;
      final position = rows.single["position"] as int;
      if (position == 0) return true;
      await txn.execute(
        "UPDATE queue SET position = position + 1 WHERE position < ?",
        [position],
      );
      await txn.update(
        "queue",
        {"position": 0},
        where: "id = ?",
        whereArgs: [entryId],
      );
      return true;
    });
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

  /// 整表替换待播条目；会话队列由 Playback 独立持有。
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

  /// 批量移除同曲全部排队记录，不用于单条菜单或点播，
  /// 删后重排 position 保持连续（takeFirst/move 依赖连续位）
  Future<void> removeByTrackId(String trackId) async {
    await db.transaction((txn) async {
      await txn.delete("queue", where: "track_id = ?", whereArgs: [trackId]);
      final rows = await txn.query("queue", columns: ["id"], orderBy: "position");
      for (final (i, row) in rows.indexed) {
        await txn.update(
          "queue",
          {"position": i},
          where: "id = ?",
          whereArgs: [row["id"] as int],
        );
      }
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
