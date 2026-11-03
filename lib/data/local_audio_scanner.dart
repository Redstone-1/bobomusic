import "dart:async";
import "dart:io";
import "dart:isolate";

import "package:audio_metadata_reader/audio_metadata_reader.dart" as amr;

import "models/track.dart";

/// 原始元数据（读出即止；指纹由扫描器统一计算）
class RawAudioMeta {
  final String? title;
  final String? artist;
  final int? durationMs;

  const RawAudioMeta({this.title, this.artist, this.durationMs});
}

/// 元数据读取抽象：默认走 audio_metadata_reader，测试注入 fake 避开真文件解析
abstract class AudioMetadataSource {
  RawAudioMeta read(File file);
}

class DefaultAudioMetadataSource implements AudioMetadataSource {
  @override
  RawAudioMeta read(File file) {
    final meta = amr.readMetadata(file, getImage: false);
    return RawAudioMeta(
      title: meta.title,
      artist: meta.artist,
      durationMs: meta.duration?.inMilliseconds,
    );
  }
}

/// 单个文件读取失败（路径 + 原因，供扫描结果面板展示）
class ScanFailure {
  final String path;
  final String reason;

  const ScanFailure({required this.path, required this.reason});
}

/// 扫描结果：入库形状的本地曲目 + 失败文件
class LocalScanResult {
  final List<Track> tracks;
  final List<String> failed;

  /// 结构化的失败列表（`failed` 保留为路径列表，兼容旧调用）
  final List<ScanFailure> failures;
  final List<String> roots;
  final List<String> inaccessibleDirectories;

  const LocalScanResult({
    required this.tracks,
    required this.failed,
    this.failures = const [],
    this.roots = const [],
    this.inaccessibleDirectories = const [],
  });
}

/// 扫描流式事件（UI 用文件名滚动与计数；不持有扫描器内部状态）
sealed class LocalScanEvent {
  const LocalScanEvent();
}

/// 一批已遍历的音频文件（批量发送，降低 isolate 消息频率）
class LocalScanFiles extends LocalScanEvent {
  final List<String> paths;

  const LocalScanFiles(this.paths);
}

/// 单个文件读取失败
class LocalScanFileFailure extends LocalScanEvent {
  final String path;
  final String reason;

  const LocalScanFileFailure(this.path, this.reason);
}

/// 累计进度（已遍历 / 已入库 / 失败）
class LocalScanProgress extends LocalScanEvent {
  final int scanned;
  final int indexed;
  final int failed;

  const LocalScanProgress({
    required this.scanned,
    required this.indexed,
    required this.failed,
  });
}

/// 扫描完成
class LocalScanDone extends LocalScanEvent {
  final LocalScanResult result;

  const LocalScanDone(this.result);
}

/// 扫描任务句柄：订阅 [events] 获取进度，[cancel] 立即终止后台 isolate
class LocalScanTask {
  final Stream<LocalScanEvent> events;
  final void Function() cancel;

  const LocalScanTask({required this.events, required this.cancel});
}

typedef _ScanEmitter = void Function(LocalScanEvent event);

/// 本地内容指纹（§3.4-9）：大小 + 时长 + 归一化标题/歌手
/// 归一化 = 去全部空白 + 小写（中文标题空格有无不稳定；英文极端碰撞由大小/时长兜底）
/// → 重扫同一文件得到同一 id，upsert 语义天然保留 liked/歌词
String localAudioFingerprint({
  required int sizeBytes,
  required int durationSec,
  required String title,
  required String artist,
}) {
  String norm(String s) => s.replaceAll(RegExp(r"\s+"), "").toLowerCase();
  return "local:$sizeBytes:$durationSec:${norm(title)}:${norm(artist)}";
}

/// 本地音频扫描器（C3）
/// 生产路径在独立 isolate 中遍历并流式回传文件/进度；
/// 注入 [AudioMetadataSource]（测试）时主 isolate 直跑，事件仍走同一套流。
class LocalAudioScanner {
  /// 音频扩展名白名单（沿 2.7.0）
  static const audioExtensions = {
    ".mp3",
    ".wav",
    ".flac",
    ".m4a",
    ".aac",
    ".ogg",
    ".opus",
  };

  /// 判定目录是否排除：名为 Android 的目录（系统私有，不可访问且巨大）、
  /// Download/啵啵音乐（App 下载目录，§3.4-8 防与在线下载条目重复）
  static bool isExcludedDir(Directory dir) {
    final normalized = dir.path.replaceAll("\\", "/");
    if (normalized.split("/").contains("Android")) return true;
    final lower = normalized.toLowerCase();
    if (lower.contains("/download/啵啵音乐") || lower.contains("/downloads/啵啵音乐")) {
      return true;
    }
    return false;
  }

  /// 一次性扫描（兼容旧调用/导入）；内部消费 [scanTask] 事件流
  Future<LocalScanResult> scan({
    required List<Directory> roots,
    AudioMetadataSource? source,
  }) async {
    final task = scanTask(roots: roots, source: source);
    await for (final event in task.events) {
      if (event is LocalScanDone) return event.result;
    }
    return const LocalScanResult(tracks: [], failed: []);
  }

  /// 只扫描指定文件（iOS/桌面导入用；避免把历史导入条目重复计入本次数量）
  Future<LocalScanResult> scanFiles(
    List<File> files, {
    AudioMetadataSource? source,
  }) async {
    if (source != null) return _scanFilesSync(files, source);
    return Isolate.run(
      () => _scanFilesSync(files, DefaultAudioMetadataSource()),
    );
  }

  /// 流式扫描任务：生产走 Isolate + SendPort，注入 source 走主 isolate
  LocalScanTask scanTask({
    required List<Directory> roots,
    AudioMetadataSource? source,
  }) {
    if (source != null) {
      final controller = StreamController<LocalScanEvent>();
      var closed = false;
      void close() {
        if (closed) return;
        closed = true;
        if (!controller.isClosed) controller.close();
      }

      scheduleMicrotask(() {
        if (closed) return;
        final result = _scanSync(roots, source, controller.add);
        if (closed) return;
        controller.add(LocalScanDone(result));
        close();
      });
      return LocalScanTask(events: controller.stream, cancel: close);
    }

    final receivePort = ReceivePort();
    final controller = StreamController<LocalScanEvent>();
    Isolate? isolate;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      receivePort.close();
      if (!controller.isClosed) controller.close();
    }

    receivePort.listen((message) {
      if (closed) return;
      // Isolate 异常退出/提前结束：避免 controller 永久等待
      if (message == null) {
        controller.addError(StateError("扫描 isolate 提前退出"));
        close();
        return;
      }
      if (message is! List || message.isEmpty) return;
      if (message[0] is! String) {
        controller.addError(StateError("扫描 isolate 失败：${message[0]}"));
        close();
        return;
      }
      switch (message[0]) {
        case "files":
          controller.add(LocalScanFiles(List<String>.from(message[1] as List)));
        case "failure":
          controller.add(
            LocalScanFileFailure(message[1] as String, message[2] as String),
          );
        case "progress":
          controller.add(
            LocalScanProgress(
              scanned: message[1] as int,
              indexed: message[2] as int,
              failed: message[3] as int,
            ),
          );
        case "done":
          final tracks = (message[1] as List).cast<Track>();
          final failures = (message[2] as List).cast<ScanFailure>();
          controller.add(
            LocalScanDone(
              LocalScanResult(
                tracks: tracks,
                failed: [for (final f in failures) f.path],
                failures: failures,
                roots: (message[3] as List).cast<String>(),
                inaccessibleDirectories: (message[4] as List).cast<String>(),
              ),
            ),
          );
          close();
      }
    });

    Isolate.spawn(
      _scanIsolate,
      [
        receivePort.sendPort,
        [for (final root in roots) root.path],
      ],
      onExit: receivePort.sendPort,
      onError: receivePort.sendPort,
      errorsAreFatal: true,
    ).then((spawned) {
      if (closed) {
        spawned.kill(priority: Isolate.immediate);
      } else {
        isolate = spawned;
      }
    }).catchError((Object error) {
      if (!closed) {
        controller.addError(error);
        close();
      }
    });

    return LocalScanTask(
      events: controller.stream,
      cancel: () {
        isolate?.kill(priority: Isolate.immediate);
        close();
      },
    );
  }

  /// 后台 isolate 入口：同步遍历并批量回传事件
  static void _scanIsolate(List<Object?> args) {
    final send = args[0] as SendPort;
    final roots = [
      for (final path in (args[1] as List).cast<String>()) Directory(path),
    ];
    final result = _scanSync(roots, DefaultAudioMetadataSource(), (event) {
      switch (event) {
        case LocalScanFiles(:final paths):
          send.send(["files", paths]);
        case LocalScanFileFailure(:final path, :final reason):
          send.send(["failure", path, reason]);
        case LocalScanProgress(:final scanned, :final indexed, :final failed):
          send.send(["progress", scanned, indexed, failed]);
        default:
          break;
      }
    });
    send.send([
      "done",
      result.tracks,
      result.failures,
      result.roots,
      result.inaccessibleDirectories
    ]);
  }

  static LocalScanResult _scanFilesSync(
    List<File> files,
    AudioMetadataSource source,
  ) {
    final acc = _ScanAccumulator();
    for (final file in files) {
      if (_isAudio(file.path)) acc.record(file, source, (_) {});
    }
    acc.flush((_) {});
    return acc.result;
  }

  static LocalScanResult _scanSync(
    List<Directory> roots,
    AudioMetadataSource source,
    _ScanEmitter emit,
  ) {
    final acc = _ScanAccumulator();
    final inaccessible = <String>[];
    for (final root in roots) {
      if (isExcludedDir(root)) {
        inaccessible.add(root.absolute.path);
        continue;
      }
      _walk(root, source, acc, emit, inaccessible);
    }
    acc.flush(emit);
    final result = acc.result;
    final failures = [
      ...result.failures,
      for (final path in inaccessible)
        ScanFailure(path: path, reason: "目录不可访问，本次不清理缺失音乐")
    ];
    return LocalScanResult(
        tracks: result.tracks,
        failed: [for (final failure in failures) failure.path],
        failures: failures,
        roots: [for (final root in roots) root.absolute.path],
        inaccessibleDirectories: inaccessible);
  }

  /// 目录拒访必须进入结果，不能让缺失清理把权限失败当成文件已删除。
  static void _walk(
    Directory dir,
    AudioMetadataSource source,
    _ScanAccumulator acc,
    _ScanEmitter emit,
    List<String> inaccessible,
  ) {
    final List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false);
    } catch (error) {
      inaccessible.add(dir.absolute.path);
      emit(LocalScanFileFailure(dir.path, "目录不可访问：$error"));
      return;
    }
    for (final entity in entities) {
      if (entity is Directory) {
        if (!isExcludedDir(entity)) {
          _walk(entity, source, acc, emit, inaccessible);
        }
      } else if (entity is File && _isAudio(entity.path)) {
        acc.record(entity, source, emit);
      }
    }
  }

  static bool _isAudio(String path) {
    final lower = path.toLowerCase();
    return audioExtensions.any(lower.endsWith);
  }

  /// 单文件读元数据：标题缺失回退文件名；歌手缺失记「未知歌手」（沿 2.7.0 文案）
  static _ReadResult _read(File file, AudioMetadataSource source) {
    try {
      final meta = source.read(file);
      final fileTitle = file.path
          .replaceAll("\\", "/")
          .split("/")
          .last
          .replaceFirst(RegExp(r"\.[^.]+$"), "");
      final title =
          (meta.title ?? "").trim().isNotEmpty ? meta.title!.trim() : fileTitle;
      final artist = (meta.artist ?? "").trim();
      final durationSec = ((meta.durationMs ?? 0) / 1000).round();
      return _ReadResult(
        track: Track(
          id: localAudioFingerprint(
            sizeBytes: file.lengthSync(),
            durationSec: durationSec,
            title: title,
            artist: artist,
          ),
          name: title,
          author: artist.isEmpty ? "未知歌手" : artist,
          duration: durationSec,
          origin: OriginType.local,
          localPath: file.path,
        ),
      );
    } catch (e) {
      return _ReadResult(
        failure: ScanFailure(path: file.path, reason: _failureReason(e)),
      );
    }
  }

  static String _failureReason(Object error) {
    final text = error.toString().replaceAll("\n", " ").trim();
    return text.isEmpty ? "元数据解析失败" : "读取失败：$text";
  }
}

/// 扫描过程的累计状态：批量发送文件事件与进度，避免每个文件都过通道
class _ScanAccumulator {
  final tracks = <Track>[];
  final failures = <ScanFailure>[];
  final pendingPaths = <String>[];
  int scanned = 0;
  int indexed = 0;
  int failed = 0;

  LocalScanResult get result => LocalScanResult(
        tracks: tracks,
        failed: [for (final failure in failures) failure.path],
        failures: failures,
      );

  void record(File file, AudioMetadataSource source, _ScanEmitter emit) {
    scanned++;
    final read = LocalAudioScanner._read(file, source);
    if (read.track case final track?) {
      tracks.add(track);
      indexed++;
      pendingPaths.add(file.path);
    } else if (read.failure case final failure?) {
      failures.add(failure);
      failed++;
      emit(LocalScanFileFailure(failure.path, failure.reason));
    }
    if (pendingPaths.length >= 8 || scanned % 8 == 0) flush(emit);
  }

  void flush(_ScanEmitter emit) {
    if (pendingPaths.isNotEmpty) {
      emit(LocalScanFiles(List<String>.unmodifiable(pendingPaths)));
      pendingPaths.clear();
    }
    emit(LocalScanProgress(scanned: scanned, indexed: indexed, failed: failed));
  }
}

class _ReadResult {
  final Track? track;
  final ScanFailure? failure;

  const _ReadResult({this.track, this.failure});
}

/// 可替换全局：测试注入扫描结果（跳过权限/文件系统/Isolate，同 appDb 等环境单例模式）
LocalScanResult? localScanTestOverride;

/// 流式扫描入口（生产用）：按平台解析根目录后返回任务
LocalScanTask scanLocalLibraryTask({List<Directory>? roots}) {
  if (localScanTestOverride case final override?) {
    final controller = StreamController<LocalScanEvent>();
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      if (!controller.isClosed) controller.close();
    }

    scheduleMicrotask(() {
      if (closed) return;
      controller.add(LocalScanDone(override));
      close();
    });
    return LocalScanTask(events: controller.stream, cancel: close);
  }
  final home = Platform.environment["USERPROFILE"] ??
      Platform.environment["HOME"] ??
      ".";
  final resolvedRoots = roots ??
      <Directory>[
        if (Platform.isAndroid)
          Directory("/storage/emulated/0")
        else
          Directory("$home/Music"),
      ];
  return LocalAudioScanner().scanTask(roots: resolvedRoots);
}

/// 一次性扫描入口（兼容旧调用）：消费 [scanLocalLibraryTask] 的事件流
Future<LocalScanResult> scanLocalLibrary() async {
  final task = scanLocalLibraryTask();
  await for (final event in task.events) {
    if (event is LocalScanDone) return event.result;
  }
  return const LocalScanResult(tracks: [], failed: []);
}
