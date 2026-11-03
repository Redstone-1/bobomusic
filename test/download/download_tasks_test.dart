import "dart:io";
import "dart:async";

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
    final result =
        await container.read(downloadTasksProvider.notifier).start(track);

    expect(result.ok, isTrue, reason: result.message);
    final tasks = container.read(downloadTasksProvider);
    expect(tasks.single.status, DownloadTaskStatus.completed);
    expect(tasks.single.progress, 1);

    final downloaded = await container.read(downloadedTracksProvider.future);
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
    final result =
        await container.read(downloadTasksProvider.notifier).start(track);

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

  test("暂停后等待旧写入结束，取消不登记部分文件且不被迟到结果复活", () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => Directory("${temp.path}/out"),
      fetch: (_, target) async {
        await target.writeAsString("partial");
        entered.complete();
        await release.future;
      },
    );
    const track = Track(
        id: "bili:cancel", name: "取消", author: "歌手", origin: OriginType.bili);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tasks = container.read(downloadTasksProvider.notifier);
    final first = tasks.start(track);
    await entered.future;
    final paused = tasks.pause(track.id);
    expect(container.read(downloadTasksProvider).single.status,
        DownloadTaskStatus.paused);
    release.complete();
    await paused;
    expect((await first).interrupted, isTrue);
    expect((await TrackRepository().getById(track.id))?.localPath, isNull);
    final part = File("${temp.path}/out/${downloadFileName(track)}.part");
    expect(await part.exists(), isTrue);
    await tasks.cancel(track);
    expect(container.read(downloadTasksProvider), isEmpty);
    expect(await part.exists(), isFalse);
  });

  test("下载中取消后旧取流结束，不能转正或覆盖重新开始的同曲任务", () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    downloadDepsTestOverride = DownloadDeps(
      resolveDir: () async => Directory("${temp.path}/out"),
      fetch: (_, target) async {
        calls++;
        if (calls == 1) {
          entered.complete();
          await release.future;
        }
        await target.writeAsString("audio-$calls");
      },
    );
    const track = Track(
        id: "bili:restart", name: "重试", author: "歌手", origin: OriginType.bili);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tasks = container.read(downloadTasksProvider.notifier);
    final first = tasks.start(track);
    await entered.future;
    final cancel = tasks.cancel(track);
    final second = tasks.start(track);
    expect(container.read(downloadTasksProvider), isEmpty);
    release.complete();
    await cancel;
    expect((await first).interrupted, isTrue);
    final result = await second;
    expect(result.ok, isTrue);
    expect(await File(result.path!).readAsString(), "audio-2");
    expect(container.read(downloadTasksProvider).single.status,
        DownloadTaskStatus.completed);
  });
}
