import "dart:io";

import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

const windowsDatabaseFileName = "bobomusic3.db";

/// 旧 FFI 库可能位于启动目录或可执行文件旁；不递归搜索用户磁盘猜测旧库。
List<String> windowsLegacyDatabasePaths({
  required String legacyDatabaseDirectory,
  required String workingDirectory,
  required String executableDirectory,
}) =>
    <String>{
      p.join(legacyDatabaseDirectory, windowsDatabaseFileName),
      p.join(executableDirectory, ".dart_tool", "sqflite_common_ffi",
          "databases", windowsDatabaseFileName),
      p.join(workingDirectory, windowsDatabaseFileName),
      p.join(executableDirectory, windowsDatabaseFileName),
    }.map(p.absolute).toList();

/// 只在目标库不存在时迁移：SQLite 快照包含尚在 WAL 中的已提交数据，原库保持可回退。
Future<String> prepareWindowsDatabase({
  required Directory supportDirectory,
  required List<String> legacyPaths,
  required DatabaseFactory factory,
}) async {
  final directory = Directory(p.join(supportDirectory.path, "databases"));
  await directory.create(recursive: true);
  final target = File(p.join(directory.path, windowsDatabaseFileName));
  if (await target.exists()) return target.path;

  final candidates = <String>[];
  for (final path in legacyPaths.map(p.absolute).toSet()) {
    if (!p.equals(path, target.path) &&
        !candidates.any((candidate) => p.equals(candidate, path)) &&
        await File(path).exists()) {
      candidates.add(path);
    }
  }
  if (candidates.isEmpty) return target.path;
  if (candidates.length > 1) {
    throw FileSystemException(
      "检测到多份旧数据库，请先备份并确认要保留的一份：${candidates.join("；")}",
    );
  }

  final staging = File(p.join(directory.path,
      "$windowsDatabaseFileName.migrating-${DateTime.now().microsecondsSinceEpoch}"));
  Database? source;
  Database? snapshot;
  try {
    source = await factory.openDatabase(candidates.single,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    // 文件名作为参数传入，避免路径中的引号变成 SQL。
    await source.execute("VACUUM INTO ?", [staging.path]);
    await source.close();
    source = null;
    snapshot = await factory.openDatabase(staging.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    final check = await snapshot.rawQuery("PRAGMA quick_check");
    final tables = await snapshot
        .rawQuery("SELECT name FROM sqlite_master WHERE type = ?", ["table"]);
    final names = tables.map((row) => row["name"]).toSet();
    if (check.length != 1 ||
        check.single.values.single != "ok" ||
        !names
            .containsAll(["tracks", "playlists", "playlist_items", "queue"])) {
      throw const FormatException("旧数据库校验失败，原文件已保留");
    }
    await snapshot.close();
    snapshot = null;
    // Windows rename 不覆盖目标；并发启动先完成的迁移始终优先。
    if (!await target.exists()) await staging.rename(target.path);
    return target.path;
  } catch (error) {
    print("Windows 数据库迁移失败：$error");
    throw FileSystemException("旧数据库迁移失败，原文件已保留：$error", candidates.single);
  } finally {
    await snapshot?.close();
    await source?.close();
    if (await staging.exists()) await staging.delete();
  }
}
