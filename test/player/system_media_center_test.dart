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

/// 自研媒体中心桥：通道载荷序列化 + 原生命令分发（纯逻辑，不依赖平台通道）
void main() {
  const track = Track(
    id: "bili:1_BV1_2",
    name: "夜航西飞",
    author: "陈鸿宇",
    duration: 252,
    cover: "https://example.com/cover.jpg",
  );

  SystemPlaybackSnapshot snap({
    bool playing = true,
    Duration duration = const Duration(seconds: 252),
  }) =>
      SystemPlaybackSnapshot(
        track: track,
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

  test("原生命令分发：转发给状态机命令", () async {
    final center = SystemMediaCenter(const MethodChannel("test"));
    final commands = _RecordingCommands();
    center.commands = commands;
    await center.onNativeCall(const MethodCall("play"));
    await center.onNativeCall(const MethodCall("pause"));
    await center.onNativeCall(const MethodCall("next"));
    await center.onNativeCall(const MethodCall("previous"));
    await center.onNativeCall(const MethodCall("seek", 42000));
    expect(commands.calls, [
      "play",
      "pause",
      "next",
      "previous",
      "seek:42000",
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
}
