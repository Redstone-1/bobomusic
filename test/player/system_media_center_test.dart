import "dart:async";
import "dart:io";

import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/play_mode.dart";
import "package:bobomusic/features/player/system_media_center.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

class _RecordingCommands implements SystemPlaybackCommands {
  final calls = <String>[];

  @override
  Future<void> systemPlay() async => calls.add("play");

  @override
  Future<void> systemPause() async => calls.add("pause");

  @override
  Future<void> systemNext() async => calls.add("next");

  @override
  Future<void> systemPrevious() async => calls.add("previous");

  @override
  Future<void> systemSeek(Duration position) async =>
      calls.add("seek:${position.inMilliseconds}");

  @override
  Future<void> systemSetSpeed(double speed) async => calls.add("speed:$speed");

  @override
  Future<void> systemStop() async => calls.add("stop");
}

/// 冲刷事件队列：sync 内部的封面解析/补推均为未等待的异步链，需要数个事件轮转落地
Future<void> drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// 自研媒体中心桥：通道载荷序列化 + 原生命令分发 + 封面竞态守卫
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SystemPlaybackSnapshot snap({
    bool playing = true,
    Duration duration = const Duration(seconds: 252),
    String cover = "https://example.com/cover.jpg",
  }) =>
      SystemPlaybackSnapshot(
        track: Track(
          id: "bili:1_BV1_2",
          name: "夜航西飞",
          author: "陈鸿宇",
          duration: 252,
          cover: cover,
        ),
        playing: playing,
        buffering: false,
        position: const Duration(seconds: 30),
        duration: duration,
        mode: PlayMode.listLoop,
        queueIndex: 2,
      );

  test("mediaStateMap：快照序列化为通道载荷", () {
    final map = mediaStateMap(snap(), coverPath: "/cache/cover.jpg");
    expect(map["title"], "夜航西飞");
    expect(map["id"], "bili:1_BV1_2");
    expect(map["artist"], "陈鸿宇");
    expect(map["coverPath"], "/cache/cover.jpg");
    expect(map["durationMs"], 252000);
    expect(map["positionMs"], 30000);
    expect(map["playing"], isTrue);
    expect(map["buffering"], isFalse);
    expect(map["speed"], 1.0);
  });

  test("mediaStateMap：时长未就绪回退曲目元数据", () {
    final map = mediaStateMap(snap(duration: Duration.zero));
    expect(map["durationMs"], 252000);
  });

  test("mediaStateMap：显示名覆盖优先（本地改名后通知栏同步）", () {
    final map = mediaStateMap(
      SystemPlaybackSnapshot(
        track: Track(
          id: "bili:1_BV1_2",
          name: "原始标题",
          author: "原始歌手",
          duration: 252,
          cover: "https://example.com/cover.jpg",
          displayName: "改后标题",
        ),
        playing: true,
        buffering: false,
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 252),
        mode: PlayMode.listLoop,
        queueIndex: 2,
      ),
    );
    expect(map["title"], "改后标题");
    expect(map["artist"], "原始歌手");
  });

  test("原生命令分发：转发给状态机命令", () async {
    final center = SystemMediaCenter(const MethodChannel("test"));
    final commands = _RecordingCommands();
    center.commands = commands;
    await center.onNativeCall(const MethodCall("play"));
    await center.onNativeCall(const MethodCall("pause"));
    await center.onNativeCall(const MethodCall("next"));
    await center.onNativeCall(const MethodCall("previous"));
    await center.onNativeCall(const MethodCall("seek", 42000));
    await center.onNativeCall(const MethodCall("setSpeed", 1.5));
    await center.onNativeCall(const MethodCall("stop"));
    await center.onNativeCall(const MethodCall("setSpeed", 99));
    expect(commands.calls, [
      "play",
      "pause",
      "next",
      "previous",
      "seek:42000",
      "speed:1.5",
      "stop",
    ]);
  });

  test("原生命令分发：无命令实现或未知方法不抛", () async {
    final center = SystemMediaCenter(const MethodChannel("test"));
    await center.onNativeCall(const MethodCall("play"));
    final commands = _RecordingCommands();
    center.commands = commands;
    await center.onNativeCall(const MethodCall("unknown"));
    expect(commands.calls, isEmpty);
  });

  test("封面解析完成后补推 update（首推无封面）", () async {
    const channel = MethodChannel("media_center_test.a");
    final updates = <Map<String, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == "update") {
        updates.add(Map<String, Object?>.from(call.arguments as Map));
      }
      return null;
    });
    final center = SystemMediaCenter(channel);
    final gate = Completer<File>();
    center.coverFetcher =
        (url) => gate.future.then((_) => File("/cache/ready.jpg"));
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    center.sync(snap());
    await drain();
    expect(updates, hasLength(1));
    expect(updates.first["coverPath"], isNull); // 首推：封面未就绪

    gate.complete(File("/cache/ready.jpg"));
    await drain();
    expect(updates, hasLength(2)); // 就绪补推
    expect(updates.last["coverPath"], "/cache/ready.jpg");
  });

  test("换歌竞态：旧封面迟到不回推也不覆盖当前封面路径", () async {
    const channel = MethodChannel("media_center_test.b");
    final updates = <Map<String, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == "update") {
        updates.add(Map<String, Object?>.from(call.arguments as Map));
      }
      return null;
    });
    final center = SystemMediaCenter(channel);
    final gateA = Completer<File>();
    center.coverFetcher = (url) => url.contains("a.jpg")
        ? gateA.future
        : Future<File>.value(File("/cache/b.jpg"));
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    center.sync(snap(cover: "http://x/a.jpg")); // a：拉取挂起
    await drain();
    center.sync(snap(cover: "http://x/b.jpg")); // 换 b：立即就绪
    await drain();
    // b 的首推与补推在同一个事件轮转内完成
    expect(updates, hasLength(3));
    expect(updates.last["coverPath"], "/cache/b.jpg");

    gateA.complete(File("/cache/stale_a.jpg")); // a 迟到
    await drain();
    expect(updates, hasLength(3)); // 旧封面不得回推

    center.sync(snap(cover: "http://x/b.jpg")); // 同曲下一 tick
    await drain();
    expect(updates, hasLength(4));
    expect(updates.last["coverPath"], "/cache/b.jpg"); // 路径未被旧封面覆盖
  });

  test("同一封面 URL 不重复拉取", () async {
    const channel = MethodChannel("media_center_test.c");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final center = SystemMediaCenter(channel);
    var fetches = 0;
    center.coverFetcher = (url) {
      fetches++;
      return Future<File>.value(File("/cache/c.jpg"));
    };
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    center.sync(snap(cover: "https://x/same.jpg"));
    await drain();
    final firstPassFetches = fetches;
    expect(firstPassFetches, 1);

    center.sync(snap(cover: "https://x/same.jpg")); // 同曲同封面
    await drain();
    expect(fetches, firstPassFetches); // 命中 _coverKey 去重
  });

  test("本地自定义封面直接交给系统媒体桥，不走网络下载", () async {
    const channel = MethodChannel("media_center_test.local");
    final directory = await Directory.systemTemp.createTemp("bobo_media_cover_");
    final file = await File("${directory.path}/cover.png").writeAsBytes([1, 2, 3]);
    final ready = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == "update") {
        final update = Map<String, Object?>.from(call.arguments as Map);
        if (update["coverPath"] != null && !ready.isCompleted) ready.complete(update);
      }
      return null;
    });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    final center = SystemMediaCenter(channel);
    center.coverFetcher = (_) => throw StateError("本地封面不应联网");
    center.sync(snap(cover: file.uri.toString()));
    final update = await ready.future.timeout(const Duration(seconds: 5));
    expect(update["coverPath"], File.fromUri(file.uri).path);
  });
}
