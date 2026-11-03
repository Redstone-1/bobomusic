import "dart:async";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_cache_manager/flutter_cache_manager.dart";

import "../../data/models/track.dart";
import "../../core/widgets/cover_placeholder.dart" show coverFetchHeaders;
import "play_mode.dart";

/// 系统媒体会话命令（通知按钮 / 耳机键 / 锁屏）
/// 由 Playback 状态机实现；桥接器只做转发，不持有业务状态
abstract class SystemPlaybackCommands {
  Future<void> systemPlay();
  Future<void> systemPause();
  Future<void> systemNext();
  Future<void> systemPrevious();
  Future<void> systemSeek(Duration position);
  Future<void> systemSetSpeed(double speed);
  Future<void> systemStop();
}

/// 一次系统会话快照（避免桥接器反向依赖 Riverpod 状态类）
class SystemPlaybackSnapshot {
  final Track? track;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final PlayMode mode;
  final double speed;
  final int queueIndex;

  const SystemPlaybackSnapshot({
    required this.track,
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.mode,
    this.speed = 1.0,
    required this.queueIndex,
  });
}

/// 全局桥接实例；Android、iOS、Windows 初始化，测试默认保持 null。
SystemMediaCenter? systemMediaCenter;

const MethodChannel _mediaCenterChannel =
    MethodChannel("com.bobomusic/media_center");

/// 初始化自研媒体中心桥（通道不可用不阻塞播放）。
Future<void> initSystemMediaCenter() async {
  if (systemMediaCenter != null) return;
  final center = SystemMediaCenter(_mediaCenterChannel);
  center.attach();
  systemMediaCenter = center;
}

/// 自研媒体中心 Dart 桥：快照单向推入原生服务，原生命令转发回状态机。
/// 通道协议两端同形——android 端 MediaCenterBridge/MediaCenterService，
/// iOS 端 AppDelegate.swift 的 MediaCenterBridge。
class SystemMediaCenter {
  SystemMediaCenter(this._channel);

  final MethodChannel _channel;

  /// 状态机命令实现（原生命令的转发目标）
  SystemPlaybackCommands? commands;

  /// 封面取数函数：默认走全局磁盘缓存（含浏览器 UA）；入参为已升 https 的 URL，
  /// 测试注入替身以覆盖换歌竞态分支
  Future<File> Function(String url) coverFetcher = (url) =>
      DefaultCacheManager().getSingleFile(url, headers: coverFetchHeaders);

  SystemPlaybackSnapshot? _lastSnapshot;

  /// 已解析（或已失败）的封面 URL：同一首不重复拉取
  String? _coverKey;

  /// 封面本地缓存路径；null = 无封面或获取失败（原生侧回退 App 图标）
  String? _coverPath;

  /// 注册原生命令回调（init 时调用一次）
  void attach() {
    _channel.setMethodCallHandler(onNativeCall);
  }

  /// 引擎常驻后原生命令经此入口进入；公开便于单测
  Future<dynamic> onNativeCall(MethodCall call) async {
    final commands = this.commands;
    if (commands == null) return null;
    switch (call.method) {
      case "play":
        await commands.systemPlay();
      case "pause":
        await commands.systemPause();
      case "next":
        await commands.systemNext();
      case "previous":
        await commands.systemPrevious();
      case "seek":
        final ms = (call.arguments as num?)?.toInt() ?? 0;
        await commands.systemSeek(Duration(milliseconds: ms));
      case "setSpeed":
        final speed = (call.arguments as num?)?.toDouble();
        if (speed != null && speed.isFinite && speed >= 0.5 && speed <= 2) {
          await commands.systemSetSpeed(speed);
        }
      case "stop":
        await commands.systemStop();
    }
    return null;
  }

  /// 状态机 → 系统服务；track 为空时令服务收摊
  void sync(SystemPlaybackSnapshot snap) {
    _lastSnapshot = snap;
    if (snap.track == null) {
      _coverKey = null;
      _coverPath = null;
      _invoke("stop");
      return;
    }
    unawaited(_resolveCover(snap.track!.effectiveCover));
    _push(snap);
  }

  /// 清空系统会话（播放器销毁时）
  void detach() {
    commands = null;
    _lastSnapshot = null;
    _coverKey = null;
    _coverPath = null;
    _invoke("stop");
  }

  void _push(SystemPlaybackSnapshot snap) {
    _invoke("update", mediaStateMap(snap, coverPath: _coverPath));
  }

  void _invoke(String method, [Object? arguments]) {
    unawaited(
      _channel.invokeMethod<void>(method, arguments).catchError((Object e) {
        print("媒体中心通道异常（$method）：$e");
      }),
    );
  }

  /// 封面异步解析：磁盘缓存命中即回；就绪后仍是同一首则补推一次
  Future<void> _resolveCover(String? url) async {
    if (url == null || url.isEmpty) {
      _coverKey = null;
      _coverPath = null;
      return;
    }
    if (url == _coverKey) return;
    _coverKey = url;
    _coverPath = null;
    try {
      // 部分音源给 http 直链，统一升 https；网易等封面 CDN 拦 Dart 默认 UA，
      // 必须带浏览器 UA（实测无 UA 403，见 coverFetchHeaders 注释）
      final file = await coverFetcher(url.replaceFirst("http://", "https://"));
      // 迟到的旧封面：换歌竞态守卫——既不覆盖当前路径也不回推
      if (url != _coverKey) return;
      _coverPath = file.path;
      final last = _lastSnapshot;
      if (last != null && last.track?.effectiveCover == url) {
        _push(last);
      }
    } catch (e) {
      print("媒体中心封面获取失败：$e");
    }
  }
}

/// 快照 → 通道载荷（纯函数，便于单测）
Map<String, Object?> mediaStateMap(
  SystemPlaybackSnapshot snap, {
  String? coverPath,
}) {
  final track = snap.track;
  final durationMs = snap.duration > Duration.zero
      ? snap.duration.inMilliseconds
      : (track?.duration != null ? track!.duration! * 1000 : 0);
  return {
    "id": track?.id ?? "",
    // 显示名优先：曲目被本地改名后通知栏/锁屏同步生效
    "title": track?.effectiveName ?? "",
    "artist": track?.effectiveAuthor ?? "",
    "coverPath": coverPath,
    "durationMs": durationMs,
    "positionMs": snap.position.inMilliseconds,
    "playing": snap.playing,
    "buffering": snap.buffering,
    "speed": snap.speed,
  };
}
