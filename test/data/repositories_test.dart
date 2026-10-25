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

    test("歌词校准偏移：写读一致、upsert 保留、换歌词归零", () async {
      await tracks.upsert(t("lyric:1"));
      await tracks.updateLyric("lyric:1", "[00:01.00]词");
      await tracks.updateLyricOffset("lyric:1", 500);
      expect((await tracks.getById("lyric:1"))?.lyricOffsetMs, 500);

      // 元数据刷新（upsert）不能覆盖用户校准
      await tracks.upsert(t("lyric:1", name: "改名"));
      expect((await tracks.getById("lyric:1"))?.lyricOffsetMs, 500);

      // 应用新歌词 = 校准归零
      await tracks.updateLyric("lyric:1", "[00:02.00]新词");
      expect((await tracks.getById("lyric:1"))?.lyricOffsetMs, 0);
    });
  });

  group("syncLocalTracks（C3 本地扫描同步）", () {
    Track local(String id, String name,
            {String path = "/sdcard/a.mp3", int duration = 100}) =>
        Track(
          id: id,
          name: name,
          author: "歌手",
          duration: duration,
          origin: OriginType.local,
          localPath: path,
        );

    test("首扫入库 + localTracks/localCount", () async {
      await tracks.syncLocalTracks([local("local:1:100:a:b", "曲一"), local("local:2:200:c:d", "曲二")]);
      expect((await tracks.localTracks()).length, 2);
      expect(await tracks.localCount(), 2);
    });

    test("重扫同指纹：liked/歌词保留、元数据更新（§3.4-9）", () async {
      await tracks.syncLocalTracks([local("local:1:100:a:b", "旧标题")]);
      await tracks.setLiked("local:1:100:a:b", true);
      await tracks.updateLyric("local:1:100:a:b", "[00:01.00]词");
      // 同文件重扫：id 不变，仅标题/时长等元数据刷新
      await tracks.syncLocalTracks([local("local:1:100:a:b", "新标题", duration: 120)]);
      final got = await tracks.getById("local:1:100:a:b");
      expect(got?.name, "新标题");
      expect(got?.duration, 120);
      expect(got?.liked, isTrue); // 喜欢未丢
      expect(got?.lyric, "[00:01.00]词"); // 歌词未丢
    });

    test("重扫缺失：条目删除且歌单引用级联清理", () async {
      final p = await playlists.create("我的歌单");
      await tracks.syncLocalTracks([local("local:1:100:a:b", "曲一"), local("local:2:200:c:d", "曲二")]);
      await playlists.addTrack(p.id, "local:1:100:a:b");
      expect((await playlists.items(p.id)).length, 1);
      // 曲一文件已被用户删除 → 只扫到曲二
      await tracks.syncLocalTracks([local("local:2:200:c:d", "曲二")]);
      expect(await tracks.getById("local:1:100:a:b"), isNull);
      expect((await tracks.localTracks()).map((e) => e.id), ["local:2:200:c:d"]);
      expect((await playlists.items(p.id)).length, 0); // FK 级联
      expect(await tracks.localCount(), 1);
    });

    test("空扫描：清空全部本地条目", () async {
      await tracks.syncLocalTracks([local("local:1:100:a:b", "曲一")]);
      await tracks.syncLocalTracks(const []);
      expect(await tracks.localCount(), 0);
    });

    test("超过 900 首重扫：只删未再现条目，现存条目不被误删", () async {
      // 回归：旧实现按 NOT IN 分批删除，首批会把后续批次的曲目全部删掉
      final all = [
        for (var i = 0; i < 950; i++) local("local:$i:100:t$i:a", "曲$i"),
      ];
      await tracks.syncLocalTracks(all);
      expect(await tracks.localCount(), 950);

      // 只保留前 901 首（跨过 900 分批边界）
      await tracks.syncLocalTracks(all.sublist(0, 901));
      expect(await tracks.localCount(), 901);
      expect(await tracks.getById("local:0:100:t0:a"), isNotNull);
      expect(await tracks.getById("local:900:100:t900:a"), isNotNull);
      expect(await tracks.getById("local:901:100:t901:a"), isNull);
      expect(await tracks.getById("local:949:100:t949:a"), isNull);
    });

    test("超过 900 首全量重扫：全部保留且喜欢/歌词不丢", () async {
      final all = [
        for (var i = 0; i < 950; i++) local("local:$i:100:t$i:a", "曲$i"),
      ];
      await tracks.syncLocalTracks(all);
      await tracks.setLiked("local:0:100:t0:a", true);
      await tracks.updateLyric("local:0:100:t0:a", "[00:01.00]词");
      await tracks.syncLocalTracks(all);
      expect(await tracks.localCount(), 950);
      final kept = await tracks.getById("local:0:100:t0:a");
      expect(kept?.liked, isTrue);
      expect(kept?.lyric, "[00:01.00]词");
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
