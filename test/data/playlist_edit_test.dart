import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/models/track_display_edit.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late TrackRepository tracks;
  late PlaylistRepository playlists;
  setUp(() async {
    await initAppDatabase(path: inMemoryDatabasePath);
    tracks = TrackRepository();
    playlists = PlaylistRepository();
    for (final id in ["a", "b", "c"]) {
      await tracks.upsert(Track(
          id: id,
          name: "原歌名$id",
          author: "原歌手",
          cover: "https://original/$id.jpg",
          lyric: "歌词",
          localPath: "本地路径"));
    }
  });
  tearDown(() => appDb.close());

  for (final cover in [false, true]) {
    test("${cover ? "封面" : "歌手"}校验项不创建覆盖、不更新时间或生成撤销", () async {
      final before = (await tracks.getById("b"))!;
      final row =
          (await appDb.query("tracks", where: "id = ?", whereArgs: ["b"]))
              .single;
      final undo = await tracks.updateDisplayBatch([
        const TrackDisplayEdit(trackId: "a", author: "新歌手", updateAuthor: true),
        TrackDisplayEdit(
            trackId: "b",
            author: before.effectiveAuthor,
            cover: before.effectiveCover,
            updateAuthor: !cover,
            updateCover: cover,
            validateOnly: true,
            expected: before),
      ]);
      expect(undo.map((edit) => edit.trackId), ["a"]);
      expect(
          (await appDb.query("tracks", where: "id = ?", whereArgs: ["b"]))
              .single,
          row);
      await tracks.updateDisplayBatch(undo);
      expect((await tracks.getById("a"))!.displayAuthor, isNull);
    });

    test("${cover ? "封面" : "歌手"}校验项发生变化时，前面的写入一起回滚", () async {
      final before = (await tracks.getById("b"))!;
      await tracks.updateDisplayBatch([
        TrackDisplayEdit(
            trackId: "b",
            author: "后续歌手",
            cover: "https://later/b.jpg",
            updateAuthor: !cover,
            updateCover: cover),
      ]);
      await expectLater(
          tracks.updateDisplayBatch([
            const TrackDisplayEdit(
                trackId: "a", author: "新歌手", updateAuthor: true),
            TrackDisplayEdit(
                trackId: "b",
                updateAuthor: !cover,
                updateCover: cover,
                validateOnly: true,
                expected: before),
          ]),
          throwsStateError);
      expect((await tracks.getById("a"))!.displayAuthor, isNull);
    });
  }

  test("已选不变项在预览后被删除时，整批写入回滚", () async {
    final before = (await tracks.getById("b"))!;
    await appDb.delete("tracks", where: "id = ?", whereArgs: ["b"]);
    await expectLater(
        tracks.updateDisplayBatch([
          const TrackDisplayEdit(
              trackId: "a", author: "新歌手", updateAuthor: true),
          TrackDisplayEdit(
              trackId: "b",
              updateAuthor: true,
              validateOnly: true,
              expected: before),
        ]),
        throwsStateError);
    expect((await tracks.getById("a"))!.displayAuthor, isNull);
  });

  test("歌单独立封面优先，恢复默认后回退成员封面", () async {
    final p = await playlists.create("歌单");
    await playlists.addTrack(p.id, "a");
    await playlists.updateInfo(p.id,
        name: "新歌单", customCover: "https://custom/p.jpg");
    final stored = (await playlists.getById(p.id))!;
    expect(stored.name, "新歌单");
    expect(stored.cover, "https://custom/p.jpg");
    expect((await tracks.getById("a"))!.displayCover, isNull);
    await playlists.updateInfo(p.id, name: "新歌单");
    expect((await playlists.list()).single.cover, "https://original/a.jpg");
  });

  test("批量封面共享但不绑定未来歌曲，保留其他显示字段及原始信息", () async {
    final p = await playlists.create("歌单");
    final other = await playlists.create("另一歌单");
    await playlists.addTrack(p.id, "a");
    await playlists.addTrack(other.id, "a");
    await tracks.updateDisplayInfo("a", name: "手动歌名", author: "手动歌手");
    await tracks.setLiked("a", true);
    await playlists.updateInfo(p.id,
        name: "歌单",
        customCover: "https://custom/p.jpg",
        applyCoverToTracks: true);
    final track = (await playlists.items(other.id)).single;
    expect(track.effectiveCover, "https://custom/p.jpg");
    expect(track.effectiveName, "手动歌名");
    expect(track.effectiveAuthor, "手动歌手");
    expect(track.name, "原歌名a");
    expect(track.cover, "https://original/a.jpg");
    expect(track.liked, isTrue);
    expect(track.lyric, "歌词");
    expect(track.localPath, "本地路径");
    await playlists.addTrack(p.id, "b");
    expect((await tracks.getById("b"))!.displayCover, isNull);
  });

  test("成员更新失败时歌单名称和所有已改封面一起回滚", () async {
    final p = await playlists.create("歌单");
    await playlists.addTrack(p.id, "a");
    await playlists.addTrack(p.id, "b");
    await appDb.execute("""
      CREATE TRIGGER reject_cover BEFORE UPDATE OF display_cover ON tracks
      WHEN OLD.id = 'b' BEGIN SELECT RAISE(ABORT, '拒绝写入'); END
    """);
    await expectLater(
        playlists.updateInfo(p.id,
            name: "改名",
            customCover: "https://new/p.jpg",
            applyCoverToTracks: true),
        throwsA(isA<DatabaseException>()));
    expect((await playlists.getById(p.id))!.name, "歌单");
    expect((await tracks.getById("a"))!.displayCover, isNull);
  });

  test("改名不清除封面，撤销恢复操作前覆盖而非原始名称", () async {
    await tracks.updateDisplayInfo("a",
        name: "旧自定义名", cover: "https://custom/a.jpg");
    final before = (await tracks.getById("a"))!;
    final undo = await tracks.updateDisplayBatch([
      TrackDisplayEdit(
          trackId: "a", name: "新名字", updateName: true, expected: before)
    ]);
    expect((await tracks.getById("a"))!.effectiveCover, "https://custom/a.jpg");
    await tracks.updateDisplayBatch(undo);
    expect((await tracks.getById("a"))!.displayName, "旧自定义名");
    expect((await tracks.getById("a"))!.effectiveCover, "https://custom/a.jpg");
  });

  test("预览后字段变化或歌曲删除时整批回滚", () async {
    final before = (await tracks.getById("b"))!;
    await tracks.updateDisplayInfo("b", name: "另一次编辑");
    await expectLater(
        tracks.updateDisplayBatch([
          const TrackDisplayEdit(trackId: "a", name: "第一首修改", updateName: true),
          TrackDisplayEdit(
              trackId: "b", name: "旧预览", updateName: true, expected: before),
        ]),
        throwsStateError);
    expect((await tracks.getById("a"))!.displayName, isNull);
    await expectLater(
        tracks.updateDisplayBatch([
          const TrackDisplayEdit(trackId: "a", name: "第一首修改", updateName: true),
          const TrackDisplayEdit(
              trackId: "missing", name: "不存在", updateName: true),
        ]),
        throwsStateError);
    expect((await tracks.getById("a"))!.displayName, isNull);
  });

  test("撤销只恢复涉及字段，较新的其他字段编辑保留", () async {
    final undo = await tracks.updateDisplayBatch([
      const TrackDisplayEdit(trackId: "a", name: "新名字", updateName: true),
    ]);
    await tracks.updateDisplayBatch([
      const TrackDisplayEdit(
          trackId: "a", cover: "https://later/a.jpg", updateCover: true),
    ]);
    await tracks.updateDisplayBatch(undo);
    final stored = (await tracks.getById("a"))!;
    expect(stored.displayName, isNull);
    expect(stored.effectiveCover, "https://later/a.jpg");
  });

  test("撤销遇到较新的同字段修改时整批回滚，不部分恢复其他歌曲", () async {
    final undo = await tracks.updateDisplayBatch([
      const TrackDisplayEdit(trackId: "a", name: "批量改名a", updateName: true),
      const TrackDisplayEdit(trackId: "b", name: "批量改名b", updateName: true),
    ]);
    await tracks.updateDisplayBatch([
      const TrackDisplayEdit(trackId: "b", name: "较新的编辑", updateName: true),
    ]);
    await expectLater(tracks.updateDisplayBatch(undo), throwsStateError);
    expect((await tracks.getById("a"))!.displayName, "批量改名a");
    expect((await tracks.getById("b"))!.displayName, "较新的编辑");
  });

  test("上游原始标题在预览后更新也不能被旧建议覆盖", () async {
    final before = (await tracks.getById("a"))!;
    await tracks.upsert(const Track(id: "a", name: "上游新标题", author: "原歌手"));
    await expectLater(
        tracks.updateDisplayBatch([
          TrackDisplayEdit(
              trackId: "a", name: "旧建议", updateName: true, expected: before),
        ]),
        throwsStateError);
    expect((await tracks.getById("a"))!.effectiveName, "上游新标题");
  });

  test("超过 SQLite 常见参数上限的批量改名仍可完整保存", () async {
    final batch = appDb.batch();
    for (var i = 0; i < 1001; i++) {
      batch.insert("tracks", {
        "id": "bulk$i",
        "name": "原名$i",
        "origin": "bili",
        "created_at": 1,
        "updated_at": 1
      });
    }
    await batch.commit(noResult: true);
    await tracks.updateDisplayBatch([
      for (var i = 0; i < 1001; i++)
        TrackDisplayEdit(trackId: "bulk$i", name: "新名$i", updateName: true),
    ]);
    final stored =
        await tracks.getByIds([for (var i = 0; i < 1001; i++) "bulk$i"]);
    expect(stored.length, 1001);
    expect(stored.last.effectiveName, "新名1000");
    expect((await tracks.getById("a"))!.displayName, isNull);
  });
}
