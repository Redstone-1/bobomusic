import "package:sqflite/sqflite.dart";
import "package:path/path.dart" as p;

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
        lyricOffsetMs: (row["lyric_offset"] as int?) ?? 0,
        displayName: row["display_name"] as String?,
        displayAuthor: row["display_author"] as String?,
        displayCover: row["display_cover"] as String?,
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
        "lyric_offset": track.lyricOffsetMs,
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

  /// 批量按 id 取曲（断点恢复重建会话队列用）：保持传入顺序，
  /// 库中已删除的 id 自动剔除；IN 逐 id 生成占位符并分批 ≤900（SQLite 变量上限）
  Future<List<Track>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final found = <Track>[];
    const chunkSize = 900;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = i + chunkSize > ids.length ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      final rows = await db.query(
        "tracks",
        where: "id IN (${List.filled(chunk.length, "?").join(",")})",
        whereArgs: chunk,
      );
      found.addAll([for (final r in rows) _fromRow(r)]);
    }
    final byId = {for (final t in found) t.id: t};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!
    ];
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

  /// 本地扫描同步（C3）：事务内全量 upsert + 删除本次未再现的 local 条目
  /// （playlist_items/queue 有 ON DELETE CASCADE，引用自动清理）
  /// 重扫同文件指纹 id 不变 → liked_at/lyric 由 upsert 语义保留（§3.4-9）
  Future<void> syncLocalTracks(
    List<Track> scanned, {
    List<String>? scannedRoots,
    List<String> retainedPaths = const [],
    bool removeMissing = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final track in scanned) {
        final inserted = await txn.insert(
          "tracks",
          {
            "id": track.id,
            "name": track.name,
            "author": track.author,
            "cover": track.cover,
            "duration": track.duration ?? 0,
            "origin": OriginType.local.name,
            "local_path": track.localPath,
            "lyric": track.lyric,
            "created_at": now,
            "updated_at": now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (inserted == 0) {
          await txn.update(
            "tracks",
            {
              "name": track.name,
              "author": track.author,
              "duration": track.duration ?? 0,
              "local_path": track.localPath,
              "updated_at": now,
            },
            where: "id = ?",
            whereArgs: [track.id],
          );
        }
      }
      // 删除未再现条目：先求「库内 - 本次扫描」差集，再按 id 分批 IN 删除。
      // 不能按 NOT IN 分批——每批都会把其它批的曲目当成“未再现”删掉
      // （>900 首时首批就会误删后续所有条目，喜欢/歌词/歌单引用一并丢失）。
      if (!removeMissing) return;
      final existingRows = await txn.query(
        "tracks",
        columns: ["id", "local_path"],
        where: "origin = ?",
        whereArgs: [OriginType.local.name],
      );
      final scannedIds = {for (final t in scanned) t.id};
      final staleIds = [
        for (final row in existingRows)
          if (!scannedIds.contains(row["id"] as String) &&
              !retainedPaths.any((path) =>
                  p.equals(path, row["local_path"] as String? ?? "")) &&
              (scannedRoots == null ||
                  scannedRoots.any((root) => p.isWithin(p.absolute(root),
                      p.absolute(row["local_path"] as String? ?? "")))))
            row["id"] as String,
      ];
      const chunkSize = 900; // SQLite 变量上限 999
      for (var i = 0; i < staleIds.length; i += chunkSize) {
        final end =
            i + chunkSize > staleIds.length ? staleIds.length : i + chunkSize;
        final chunk = staleIds.sublist(i, end);
        await txn.delete(
          "tracks",
          where: "id IN (${List.filled(chunk.length, "?").join(",")})",
          whereArgs: chunk,
        );
      }
    });
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

  /// 清空我喜欢（清除全部 liked_at 标记；曲目本身与歌单/队列不受影响）
  Future<void> clearLiked() async {
    await db.update(
      "tracks",
      {"liked_at": null},
      where: "liked_at IS NOT NULL",
    );
  }

  /// 写入歌词（应用新歌词时校准偏移归零）
  Future<void> updateLyric(String id, String lyric, {int offsetMs = 0}) async {
    await db.update(
      "tracks",
      {
        "lyric": lyric,
        "lyric_offset": offsetMs,
        "updated_at": DateTime.now().millisecondsSinceEpoch,
      },
      where: "id = ?",
      whereArgs: [id],
    );
  }

  /// 歌词时间校准（毫秒；正数 = 歌词延后显示）
  Future<void> updateLyricOffset(String id, int offsetMs) async {
    await db.update(
      "tracks",
      {
        "lyric_offset": offsetMs,
        "updated_at": DateTime.now().millisecondsSinceEpoch,
      },
      where: "id = ?",
      whereArgs: [id],
    );
  }

  /// 更新显示用歌名/歌手/封面（B 站等音源标题可编辑；空串 = 恢复原始值存 null）。
  /// 只写 display_* 三列：原始 name/author/cover 不动，播放/入队的网络 upsert
  /// 也不含这三列，覆盖不会被网络数据冲掉（与 liked_at/lyric 同类保护语义）
  Future<void> updateDisplayInfo(
    String id, {
    String? name,
    String? author,
    String? cover,
  }) async {
    String? normalize(String? value) {
      final text = value?.trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    await db.update(
      "tracks",
      {
        "display_name": normalize(name),
        "display_author": normalize(author),
        "display_cover": normalize(cover),
        "updated_at": DateTime.now().millisecondsSinceEpoch,
      },
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

  /// 已下载曲目（本地文件存在性由 UI 播放时再校验；按下载时间倒序）
  Future<List<Track>> downloadedTracks() async {
    final rows = await db.query(
      "tracks",
      where: "downloaded_at IS NOT NULL AND local_path IS NOT NULL",
      orderBy: "downloaded_at DESC",
    );
    return [for (final r in rows) _fromRow(r)];
  }

  /// 取消下载标记（删除文件由调用方负责；不影响喜欢/歌词/歌单引用）
  Future<void> clearDownloaded(String id) async {
    await db.update(
      "tracks",
      {"local_path": null, "downloaded_at": null},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async =>
      db.delete("tracks", where: "id = ?", whereArgs: [id]);
}
