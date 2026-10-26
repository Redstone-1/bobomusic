import "package:sqflite/sqflite.dart";

import "../db/app_database.dart";
import "../models/track.dart";
import "track_repository.dart";

/// 播放历史（最近播放）：同一曲目只保留最新时间，避免列表重复
class HistoryRepository {
  final Database db = appDb;

  HistoryRepository();

  /// 记录一次播放（同曲 REPLACE 只留最新）；track 必须已入库（外键约束）。
  /// 返回写入前的旧时间戳（毫秒，无则 null），供装载失败时用 [restore] 回滚，
  /// 避免「点了但没播出来」的曲目留在最近播放
  Future<int?> record(String trackId, {DateTime? at}) async {
    final previous = await db.query(
      "play_history",
      columns: ["played_at"],
      where: "track_id = ?",
      whereArgs: [trackId],
      limit: 1,
    );
    final previousMs = previous.isEmpty
        ? null
        : previous.first["played_at"] as int;
    await db.insert(
      "play_history",
      {
        "track_id": trackId,
        "played_at": (at ?? DateTime.now()).millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return previousMs;
  }

  /// 回滚一次未成立的播放：恢复 [previousMs] 对应的旧记录；无旧记录则整行删除
  Future<void> restore(String trackId, int? previousMs) async {
    if (previousMs == null) {
      await db.delete(
        "play_history",
        where: "track_id = ?",
        whereArgs: [trackId],
      );
      return;
    }
    await db.insert(
      "play_history",
      {"track_id": trackId, "played_at": previousMs},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 最近播放（默认 20 首，保持时间倒序；已删除曲目由 getByIds 自动剔除）
  Future<List<Track>> recent({int limit = 20}) async {
    final rows = await db.query(
      "play_history",
      columns: ["track_id"],
      orderBy: "played_at DESC",
      limit: limit,
    );
    final ids = [for (final row in rows) row["track_id"] as String];
    return TrackRepository().getByIds(ids);
  }

  Future<void> clear() async => db.delete("play_history");
}
