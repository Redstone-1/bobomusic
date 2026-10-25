import "package:flutter_test/flutter_test.dart";
import "package:bobomusic/data/models/playlist.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

/// S3.2 数据层单测：四表 schema + Repository 三件（ffi 内存库，无网络无设备）
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late TrackRepository tracks;
  late PlaylistRepository playlists;
  late QueueRepository queue;

  setUp(() async {
    await initAppDatabase(path: inMemoryDatabasePath);
    tracks = TrackRepository();
    playlists = PlaylistRepository();
    queue = QueueRepository();
  });

  Track t(String id,
          {String name = "曲", OriginType origin = OriginType.bili}) =>
      Track(id: id, name: name, author: "歌手", origin: origin, duration: 180);

  group("TrackRepository", () {
    test("upsert/getById 读写一致", () async {
      await tracks.upsert(t("bili:1_abc", name: "夜航西飞"));
      final got = await tracks.getById("bili:1_abc");
      expect(got?.name, "夜航西飞");
      expect(got?.origin, OriginType.bili);
      expect(got?.liked, isFalse);
    });

    test("upsert 保留 liked/downloaded（内容更新不覆盖喜欢态）", () async {
      await tracks.upsert(t("bili:1_abc"));
      await tracks.setLiked("bili:1_abc", true);
      await tracks.upsert(t("bili:1_abc", name: "改名了"));
      final got = await tracks.getById("bili:1_abc");
      expect(got?.name, "改名了");
      expect(got?.liked, isTrue);
    });

    test("全局喜欢：likedTracks 倒序 + setLiked 取消", () async {
      await tracks.upsert(t("a"));
      await tracks.upsert(t("b"));
      await tracks.upsert(t("c"));
      await tracks.setLiked("a", true);
      await Future.delayed(const Duration(milliseconds: 2));
      await tracks.setLiked("b", true); // 更晚 → 倒序第一
      expect(
          (await tracks.likedTracks()).map((e) => e.id).toList(), ["b", "a"]);
      await tracks.setLiked("a", false);
      expect((await tracks.likedTracks()).map((e) => e.id).toList(), ["b"]);
    });

    test("下载登记与歌词更新", () async {
      await tracks.upsert(t("local:x"));
      await tracks.markDownloaded("local:x", "/sdcard/a.m4a");
      await tracks.updateLyric("local:x", "[00:01.00]测试");
      final got = await tracks.getById("local:x");
      expect(got?.localPath, "/sdcard/a.m4a");
      expect(got?.lyric, "[00:01.00]测试");
    });
  });

  group("PlaylistRepository", () {
    test("create/list 计数与排序", () async {
      final p1 = await playlists.create("歌单一");
      await playlists.create("歌单二");
      await tracks.upsert(t("t1"));
      await playlists.addTrack(p1.id, "t1");
      final list = await playlists.list();
      expect(list.map((e) => e.name).toList(), ["歌单一", "歌单二"]);
      expect(list[0].count, 1);
      expect(list[0].type, PlaylistType.custom);
    });

    test("歌单名 UNIQUE：重复创建抛异常", () async {
      await playlists.create("唯一名");
      expect(() => playlists.create("唯一名"), throwsA(isA<DatabaseException>()));
    });

    test("addTrack 重复加入返回 false（§3.4-6）", () async {
      final p = await playlists.create("测试");
      await tracks.upsert(t("t1"));
      expect(await playlists.addTrack(p.id, "t1"), isTrue);
      expect(await playlists.addTrack(p.id, "t1"), isFalse);
      expect((await playlists.items(p.id)).length, 1);
    });

    test("items 顺序 = sort_index；reorder 重排", () async {
      final p = await playlists.create("排序");
      for (final id in ["t1", "t2", "t3"]) {
        await tracks.upsert(t(id));
        await playlists.addTrack(p.id, id);
      }
      await playlists.reorder(p.id, ["t3", "t1", "t2"]);
      expect(
        (await playlists.items(p.id)).map((e) => e.id).toList(),
        ["t3", "t1", "t2"],
      );
    });

    test("removeTrack 与删除歌单（曲目本体保留）", () async {
      final p = await playlists.create("待删");
      await tracks.upsert(t("t1"));
      await playlists.addTrack(p.id, "t1");
      await playlists.removeTrack(p.id, "t1");
      expect(await playlists.items(p.id), isEmpty);
      await playlists.delete(int.parse(p.id));
      expect(await playlists.items(p.id), isEmpty);
      expect(await tracks.getById("t1"), isNotNull); // 曲目不随歌单删除
    });

    test("rename", () async {
      final p = await playlists.create("旧名");
      await playlists.rename(int.parse(p.id), "新名");
      final list = await playlists.list();
      expect(list.single.name, "新名");
    });
  });

  group("QueueRepository", () {
    Future<void> seed() async {
      for (final id in ["t1", "t2", "t3", "t4"]) {
        await tracks.upsert(t(id));
      }
    }

    test("replaceAll + all 按 position", () async {
      await seed();
      await queue.replaceAll(["t2", "t1"]);
      expect((await queue.all()).map((e) => e.id).toList(), ["t2", "t1"]);
    });

    test("insertNext 插队，后续顺移（§3.4-5 下一首播放）", () async {
      await seed();
      await queue.replaceAll(["t1", "t2"]);
      await queue.insertNext("t3", atPosition: 1); // t1 之后
      expect((await queue.all()).map((e) => e.id).toList(), ["t1", "t3", "t2"]);
    });

    test("append 追加（稍后听）", () async {
      await seed();
      await queue.replaceAll(["t1"]);
      await queue.append("t2");
      await queue.append("t2"); // 队列允许重复
      expect((await queue.all()).map((e) => e.id).toList(), ["t1", "t2", "t2"]);
    });

    test("removeAt 移除后区间前移", () async {
      await seed();
      await queue.replaceAll(["t1", "t2", "t3"]);
      await queue.removeAt(1);
      expect((await queue.all()).map((e) => e.id).toList(), ["t1", "t3"]);
    });

    test("move 双向调序", () async {
      await seed();
      await queue.replaceAll(["t1", "t2", "t3"]);
      await queue.move(0, 2);
      expect((await queue.all()).map((e) => e.id).toList(), ["t2", "t3", "t1"]);
      await queue.move(2, 0);
      expect((await queue.all()).map((e) => e.id).toList(), ["t1", "t2", "t3"]);
    });
  });
}
