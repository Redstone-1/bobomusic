import "dart:io";

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/download/download_service.dart";
import "package:bobomusic/features/player/range_proxy_source.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

/// S5 下载模块：临时目录 + 假取流（不依赖网络/平台通道）
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory temp;
  late Directory out;
  late Directory cache;
  var fetchCalls = 0;

  setUp(() async {
    await initAppDatabase(path: inMemoryDatabasePath);
    temp = await Directory.systemTemp.createTemp("bobo_download_test");
    out = Directory("${temp.path}/out");
    cache = Directory("${temp.path}/cache")..createSync(recursive: true);
    RangeProxySource.cacheDir = cache;
    fetchCalls = 0;
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => out,
      fetch: (track, target) async {
        fetchCalls++;
        await target.parent.create(recursive: true);
        await target.writeAsString("AUDIO-${track.id}");
      },
    );
  });

  tearDown(() async {
    downloadDepsTestOverride = null;
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  Track t(String id, {String name = "夜航西飞"}) => Track(
        id: id,
        name: name,
        author: "陈鸿宇",
        duration: 200,
        origin: OriginType.bili,
      );

  test("搜索曲未入库也可下载：先 upsert 再登记 localPath", () async {
    final track = t("bili:not_in_db");
    // 故意不预先 upsert
    final result = await downloadService.download(track);

    expect(result.status, DownloadStatus.done);
    final stored = await TrackRepository().getById(track.id);
    expect(stored, isNotNull);
    expect(stored?.localPath, result.path);
  });

  test("下载在线曲：写入目标目录并登记 localPath（离线标记）", () async {
    final track = t("bili:1_BV1_2");
    await TrackRepository().upsert(track);

    final result = await downloadService.download(track);

    expect(result.status, DownloadStatus.done);
    expect(result.path, isNotNull);
    final file = File(result.path!);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), "AUDIO-bili:1_BV1_2");
    final stored = await TrackRepository().getById(track.id);
    expect(stored?.localPath, result.path);
  });

  test("播放缓存命中：直接复制，不重复取流", () async {
    final track = t("bili:cached");
    await TrackRepository().upsert(track);
    final cached = RangeProxySource.cacheFileFor(track.id);
    await cached.writeAsString("CACHED-AUDIO");

    final result = await downloadService.download(track);

    expect(result.status, DownloadStatus.done);
    expect(fetchCalls, 0);
    expect(await File(result.path!).readAsString(), "CACHED-AUDIO");
  });

  test("重复下载：返回 already，不再取流/重复占空间", () async {
    final track = t("bili:again");
    await TrackRepository().upsert(track);
    final first = await downloadService.download(track);
    expect(first.status, DownloadStatus.done);
    expect(fetchCalls, 1);

    // 模拟列表仍持旧 Track（localPath 为空），目标文件已存在
    final second = await downloadService.download(track);
    expect(second.status, DownloadStatus.already);
    expect(fetchCalls, 1);
  });

  test("取流失败：failed 且不留半成品/不写 localPath", () async {
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => out,
      fetch: (track, target) async => throw Exception("网络中断"),
    );
    final track = t("bili:fail");
    await TrackRepository().upsert(track);

    final result = await downloadService.download(track);

    expect(result.status, DownloadStatus.failed);
    expect(result.message, contains("网络中断"));
    final target = File("${out.path}/${downloadFileName(track)}");
    expect(await target.exists(), isFalse);
    expect((await TrackRepository().getById(track.id))?.localPath, isNull);
  });

  test("文件名清洗：非法字符替换、长度受限、扩展名保留", () {
    final online = downloadFileName(
      t("bili:x", name: 'a/b:c*?"<>|').copyWithName("a/b:c*?\"<>|"),
    );
    expect(RegExp(r'[\\/:*?"<>|]').hasMatch(online), isFalse);
    expect(online.endsWith(".m4a"), isTrue);
    expect(online.length <= 84, isTrue);

    final local = downloadFileName(
      const Track(
        id: "local:1",
        name: "本地",
        author: "歌手",
        origin: OriginType.local,
        localPath: "/music/a.flac",
      ),
    );
    expect(local.endsWith(".flac"), isTrue);

    // 酷我在线曲为 mp3，扩展名随音源（不再误标 .m4a）
    final kuwo = downloadFileName(
      const Track(
          id: "kuwo:1", name: "酷我曲", author: "歌手", origin: OriginType.kuwo),
    );
    expect(kuwo.endsWith(".mp3"), isTrue);
  });

  test("同名不同身份的下载互不覆盖，保留各自离线路径", () async {
    final first = await downloadService.download(t("bili:same-1"));
    final second = await downloadService.download(t("bili:same-2"));
    expect(first.path, isNot(second.path));
    expect(await File(first.path!).readAsString(), "AUDIO-bili:same-1");
    expect(await File(second.path!).readAsString(), "AUDIO-bili:same-2");
  });

  test("目标目录不可写时返回失败，不产生离线标记", () async {
    final blocked = File("${temp.path}/blocked");
    await blocked.writeAsString("占用目录名");
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => Directory("${blocked.path}/child"),
      fetch: (_, target) async => target.writeAsString("不应执行"),
    );
    final track = t("bili:disk-error");
    final result = await downloadService.download(track);
    expect(result.ok, isFalse);
    expect((await TrackRepository().getById(track.id))?.localPath, isNull);
  });
}

extension on Track {
  /// 测试辅助：仅改标题（Track 无 copyWith）
  Track copyWithName(String name) => Track(
        id: id,
        name: name,
        author: author,
        duration: duration,
        origin: origin,
      );
}
