import "dart:async";

import "package:bobomusic/data/local_audio_scanner.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/playlist/local_scan_controller.dart";
import "package:flutter_test/flutter_test.dart";

/// 扫描状态机：事件消费、计数、失败列表、取消与写库收尾
void main() {
  const track = Track(
    id: "local:1",
    name: "测试曲",
    author: "测试歌手",
    origin: OriginType.local,
    localPath: "/music/a.mp3",
  );

  test("事件流：最近路径、失败列表、计数与完成态", () async {
    final events = StreamController<LocalScanEvent>();
    final synced = <Track>[];
    final controller = LocalScanController(
      taskFactory: () =>
          LocalScanTask(events: events.stream, cancel: events.close),
      syncTracks: (tracks) async => synced.addAll(tracks),
    );
    addTearDown(controller.dispose);

    final done = controller.start();
    events.add(const LocalScanFiles(["/music/a.mp3", "/music/b.mp3"]));
    events.add(
      const LocalScanFileFailure("/music/bad.ogg", "读取失败：解析失败"),
    );
    events.add(
      const LocalScanProgress(scanned: 3, indexed: 2, failed: 1),
    );
    events.add(
      const LocalScanDone(
        LocalScanResult(
          tracks: [track],
          failed: ["/music/bad.ogg"],
          failures: [
            ScanFailure(path: "/music/bad.ogg", reason: "读取失败：解析失败"),
          ],
        ),
      ),
    );
    await events.close();
    await done;

    expect(controller.phase, LocalScanPhase.done);
    expect(controller.recentPaths, ["/music/a.mp3", "/music/b.mp3"]);
    expect(controller.failures.single.path, "/music/bad.ogg");
    expect(controller.indexed, 1);
    expect(controller.failed, 1);
    expect(synced.length, 1);
  });

  test("取消：扫描阶段回到 idle，且不写库", () async {
    final events = StreamController<LocalScanEvent>();
    var taskCancelled = false;
    var synced = false;
    final controller = LocalScanController(
      taskFactory: () => LocalScanTask(
        events: events.stream,
        cancel: () {
          taskCancelled = true;
          events.close();
        },
      ),
      syncTracks: (_) async => synced = true,
    );
    addTearDown(controller.dispose);

    final done = controller.start();
    controller.cancel();
    await done;

    expect(controller.phase, LocalScanPhase.idle);
    expect(controller.cancelled, isTrue);
    expect(taskCancelled, isTrue);
    expect(synced, isFalse);
    expect(controller.recentPaths, isEmpty);
  });

  test("写库失败：进入 failed 并保留错误信息", () async {
    final events = StreamController<LocalScanEvent>();
    final controller = LocalScanController(
      taskFactory: () =>
          LocalScanTask(events: events.stream, cancel: events.close),
      syncTracks: (_) async => throw StateError("db down"),
    );
    addTearDown(controller.dispose);

    final done = controller.start();
    events.add(const LocalScanDone(LocalScanResult(tracks: [], failed: [])));
    await events.close();
    await done;

    expect(controller.phase, LocalScanPhase.failed);
    expect(controller.error, contains("db down"));
  });

  test("旧结果只有 failed 路径时补通用原因", () async {
    final events = StreamController<LocalScanEvent>();
    final controller = LocalScanController(
      taskFactory: () =>
          LocalScanTask(events: events.stream, cancel: events.close),
      syncTracks: (_) async {},
    );
    addTearDown(controller.dispose);

    final done = controller.start();
    events.add(
      const LocalScanDone(
        LocalScanResult(tracks: [], failed: ["/music/bad.ogg"]),
      ),
    );
    await events.close();
    await done;

    expect(controller.failures.single.path, "/music/bad.ogg");
    expect(controller.failures.single.reason, "读取失败");
  });
}
