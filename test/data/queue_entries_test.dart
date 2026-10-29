import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QueueRepository queue;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await initAppDatabase(path: inMemoryDatabasePath);
    queue = QueueRepository();
    for (final id in ["a", "b", "c"]) {
      await TrackRepository().upsert(Track(id: id, name: id, author: "歌手"));
    }
  });
  tearDown(() async => appDb.close());

  Future<void> expectPositions(int length) async {
    final rows =
        await appDb.query("queue", columns: ["position"], orderBy: "position");
    expect(rows.map((row) => row["position"]),
        List.generate(length, (index) => index));
  }

  test("同曲多次排队保留独立主键，曲目读取仍保留重复顺序", () async {
    await queue.replaceAll(["a", "b", "a"]);
    final entries = await queue.entries();
    expect(entries.map((entry) => entry.id).toSet().length, 3);
    expect(entries.map((entry) => entry.track.id), ["a", "b", "a"]);
    expect((await queue.all()).map((track) => track.id), ["a", "b", "a"]);
    expect((await queue.entryById(entries.last.id))?.track.id, "a");
  });

  test("移除本条只删选中副本并紧凑排序", () async {
    await queue.replaceAll(["a", "a", "a"]);
    final before = await queue.entries();
    expect(await queue.removeEntry(before[1].id), isTrue);
    expect((await queue.entries()).map((entry) => entry.id),
        [before[0].id, before[2].id]);
    await expectPositions(2);
  });

  test("下一首播放移动已有副本到队首，不复制或影响其它副本", () async {
    await queue.replaceAll(["a", "b", "a"]);
    final before = await queue.entries();
    expect(await queue.moveEntryToFront(before.last.id), isTrue);
    final expected = [before[2].id, before[0].id, before[1].id];
    expect((await queue.entries()).map((entry) => entry.id), expected);
    expect(await queue.moveEntryToFront(before.last.id), isTrue);
    expect((await queue.entries()).map((entry) => entry.id), expected);
    await expectPositions(3);
  });

  test("队首已被播放消费后，旧菜单不会误删或移动接替位置的条目", () async {
    await queue.replaceAll(["a", "b", "c"]);
    final before = await queue.entries();
    await queue.takeFirst();
    expect(await queue.entryById(before.first.id), isNull);
    expect(await queue.removeEntry(before.first.id), isFalse);
    expect(await queue.moveEntryToFront(before.first.id), isFalse);
    expect((await queue.entries()).map((entry) => entry.id),
        [before[1].id, before[2].id]);
    await expectPositions(2);
  });

  test("整表替换后旧 id 失效，不误操作同位置新条目", () async {
    await queue.replaceAll(["a"]);
    final old = (await queue.entries()).single.id;
    await queue.replaceAll(["b"]);
    expect(await queue.removeEntry(old), isFalse);
    expect((await queue.all()).single.id, "b");
  });

  test("交错删除和置顶通过事务保持独立身份与连续位置", () async {
    await queue.replaceAll(["a", "b", "c"]);
    final before = await queue.entries();
    await Future.wait([
      queue.removeEntry(before.first.id),
      queue.moveEntryToFront(before.last.id),
    ]);
    expect((await queue.entries()).map((entry) => entry.id),
        [before.last.id, before[1].id]);
    await expectPositions(2);
  });
}
