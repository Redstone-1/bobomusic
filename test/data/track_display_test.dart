import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/queue_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

/// 显示用歌名/歌手覆盖（v5 display_name/display_author）：
/// 原始 name/author 永不被冲掉（播放/入队的网络 upsert 不含 display 列），
/// 空文本归 null 回退原始值，歌单成员与队列条目读出覆盖后的显示名
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

  Track bili({
    String name = "【4K现场】超长UP主自定义标题",
    String author = "",
  }) =>
      Track(id: "100_BV1", name: name, author: author, origin: OriginType.bili);

  test("改名后 effective 生效，原始值保留", () async {
    await tracks.upsert(bili());
    await tracks.updateDisplayInfo("100_BV1", name: "现场版", author: "歌手名");

    final stored = await tracks.getById("100_BV1");
    expect(stored!.name, "【4K现场】超长UP主自定义标题");
    expect(stored.author, "");
    expect(stored.displayName, "现场版");
    expect(stored.displayAuthor, "歌手名");
    expect(stored.effectiveName, "现场版");
    expect(stored.effectiveAuthor, "歌手名");
  });

  test("再次播放/入队 upsert 原始值不冲掉覆盖", () async {
    await tracks.upsert(bili());
    await tracks.updateDisplayInfo("100_BV1", name: "现场版");
    // 模拟播放/入队：携带网络原始 name/author 再次 upsert
    await tracks.upsert(bili());

    final stored = await tracks.getById("100_BV1");
    expect(stored!.displayName, "现场版");
    expect(stored.effectiveName, "现场版");
  });

  test("本地曲重扫 syncLocalTracks 同样不冲掉覆盖", () async {
    final local = Track(
      id: "local_x",
      name: "本地曲",
      author: "本地歌手",
      origin: OriginType.local,
    );
    await tracks.upsert(local);
    await tracks.updateDisplayInfo("local_x", name: "改后名");
    // 重扫同指纹曲目：内容字段被刷新，display 覆盖保留
    await tracks.syncLocalTracks([local]);
    expect((await tracks.getById("local_x"))!.effectiveName, "改后名");
  });

  test("空文本 = 恢复原始值", () async {
    await tracks.upsert(bili());
    await tracks.updateDisplayInfo("100_BV1", name: "现场版");
    await tracks.updateDisplayInfo("100_BV1", name: "  ", author: "");

    final stored = await tracks.getById("100_BV1");
    expect(stored!.displayName, isNull);
    expect(stored.effectiveName, "【4K现场】超长UP主自定义标题");
    expect(stored.effectiveAuthor, "");
  });

  test("封面覆盖：改后生效、清空恢复原始、upsert 不冲掉", () async {
    final withCover = Track(
      id: "200_BV2",
      name: "带封面的曲",
      author: "",
      cover: "https://original.example/cover.jpg",
      origin: OriginType.bili,
    );
    await tracks.upsert(withCover);
    await tracks.updateDisplayInfo("200_BV2",
        cover: "https://custom.example/c.jpg");

    final edited = await tracks.getById("200_BV2");
    expect(edited!.cover, "https://original.example/cover.jpg"); // 原始保留
    expect(edited.effectiveCover, "https://custom.example/c.jpg");

    // 播放/入队 upsert 原始值不冲掉封面覆盖
    await tracks.upsert(withCover);
    expect(
      (await tracks.getById("200_BV2"))!.effectiveCover,
      "https://custom.example/c.jpg",
    );

    // 清空 = 恢复原始封面
    await tracks.updateDisplayInfo("200_BV2", cover: "  ");
    final cleared = (await tracks.getById("200_BV2"))!;
    expect(cleared.displayCover, isNull);
    expect(cleared.effectiveCover, "https://original.example/cover.jpg");
  });

  test("桌面歌单封面优先使用自定义封面，清空后恢复原图", () async {
    await tracks.upsert(const Track(
      id: "desktop-cover",
      name: "封面测试",
      author: "测试歌手",
      cover: "https://original.example/cover.jpg",
    ));
    final playlist = await playlists.create("封面歌单");
    await playlists.addTrack(playlist.id, "desktop-cover");
    await tracks.updateDisplayInfo("desktop-cover",
        cover: "https://custom.example/cover.jpg");
    expect((await playlists.list()).single.cover,
        "https://custom.example/cover.jpg");
    await tracks.updateDisplayInfo("desktop-cover", cover: "");
    expect((await playlists.list()).single.cover,
        "https://original.example/cover.jpg");
  });

  test("歌单成员与队列条目读出覆盖后的显示名", () async {
    await tracks.upsert(bili());
    await tracks.updateDisplayInfo("100_BV1", name: "现场版", author: "歌手名");

    final playlist = await playlists.create("我的歌单");
    await playlists.addTrack(playlist.id, "100_BV1");
    final items = await playlists.items(playlist.id);
    expect(items.single.effectiveName, "现场版");
    expect(items.single.effectiveAuthor, "歌手名");

    await queue.append("100_BV1");
    final entries = await queue.entries();
    expect(entries.single.track.effectiveName, "现场版");
    expect(entries.single.track.effectiveAuthor, "歌手名");
  });
}
