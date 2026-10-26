import "dart:io";

import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/download/download_service.dart";
import "package:bobomusic/features/download/download_tasks.dart";
import "package:bobomusic/features/player/range_proxy_source.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() {
  late Directory temp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await initAppDatabase(path: inMemoryDatabasePath);
    temp = await Directory.systemTemp.createTemp("bobo_download_task");
    final out = Directory("${temp.path}/out");
    RangeProxySource.cacheDir = Directory("${temp.path}/cache")
      ..createSync(recursive: true);
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => out,
      fetch: (track, target) async {
        await target.parent.create(recursive: true);
        await target.writeAsString("audio-${track.id}");
      },
    );
  });

  tearDown(() async {
    downloadDepsTestOverride = null;
    await temp.delete(recursive: true);
  });

  test("下载任务：成功进入已完成并刷新已下载列表", () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const track = Track(
      id: "bili:task",
      name: "任务歌曲",
      author: "歌手",
      origin: OriginType.bili,
    );
    final result = await container
        .read(downloadTasksProvider.notifier)
        .start(track);

    expect(result.ok, isTrue, reason: result.message);
    final tasks = container.read(downloadTasksProvider);
    expect(tasks.single.status, DownloadTaskStatus.completed);
    expect(tasks.single.progress, 1);

    final downloaded =
        await container.read(downloadedTracksProvider.future);
    expect(downloaded.single.id, track.id);
  });

  test("下载任务：失败保留任务供重试", () async {
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => Directory("${temp.path}/out"),
      fetch: (track, target) async => throw StateError("网络断开"),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const track = Track(
      id: "bili:fail",
      name: "失败歌曲",
      author: "歌手",
      origin: OriginType.bili,
    );
    final result = await container
        .read(downloadTasksProvider.notifier)
        .start(track);

    expect(result.ok, isFalse);
    final tasks = container.read(downloadTasksProvider);
    expect(tasks.single.status, DownloadTaskStatus.failed);
    final stored = await TrackRepository().getById(track.id);
    expect(
      stored?.localPath,
      isNull,
      reason: "失败不应产生可播放的下载登记",
    );
  });
}
