import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/history_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

Track _track(String id) => Track(
      id: id,
      name: "歌曲$id",
      author: "歌手",
      origin: OriginType.bili,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await initAppDatabase(path: inMemoryDatabasePath);
  });

  test("最近播放：同曲去重、按最新播放时间倒序", () async {
    final repo = TrackRepository();
    await repo.upsert(_track("a"));
    await repo.upsert(_track("b"));
    final history = HistoryRepository();

    await history.record("a", at: DateTime(2026, 1, 1, 10));
    await history.record("b", at: DateTime(2026, 1, 1, 10, 1));
    await history.record("a", at: DateTime(2026, 1, 1, 10, 2));

    final recent = await history.recent();
    expect(recent.map((t) => t.id), ["a", "b"]);
  });

  test("最近播放：曲目删除后级联清理", () async {
    final repo = TrackRepository();
    await repo.upsert(_track("a"));
    await repo.upsert(_track("b"));
    final history = HistoryRepository();
    await history.record("a", at: DateTime(2026, 1, 1, 10));
    await history.record("b", at: DateTime(2026, 1, 1, 10, 1));

    await repo.delete("a");
    final recent = await history.recent();
    expect(recent.map((t) => t.id), ["b"]);
  });

  test("最近播放：清空只删记录，不删曲目", () async {
    final repo = TrackRepository();
    await repo.upsert(_track("a"));
    final history = HistoryRepository();
    await history.record("a");

    await history.clear();
    expect(await history.recent(), isEmpty);
    expect(await repo.getById("a"), isNotNull);
  });

  test("装载失败回滚：有旧记录恢复旧时间戳，无旧记录整行删除", () async {
    final repo = TrackRepository();
    await repo.upsert(_track("a"));
    await repo.upsert(_track("b"));
    final history = HistoryRepository();

    await history.record("a", at: DateTime(2026, 1, 1, 10));
    // 再次播放 a：record 返回旧时间戳，回滚后恢复
    final prevA = await history.record("a", at: DateTime(2026, 1, 2));
    expect(prevA, DateTime(2026, 1, 1, 10).millisecondsSinceEpoch);
    await history.restore("a", prevA);
    final recent = await history.recent();
    expect(recent.map((t) => t.id), ["a"]);
    // 回滚的是 REPLACE 前旧值：时间戳回到 1 日 10 点
    final rows = await history.db
        .query("play_history", where: "track_id = ?", whereArgs: ["a"]);
    expect(rows.first["played_at"],
        DateTime(2026, 1, 1, 10).millisecondsSinceEpoch);

    // 首次播放 b 失败：无旧记录 → 整行删除
    final prevB = await history.record("b", at: DateTime(2026, 1, 3));
    expect(prevB, isNull);
    await history.restore("b", null);
    expect((await history.recent()).map((t) => t.id), ["a"]);
  });
}
