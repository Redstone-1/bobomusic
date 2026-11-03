import "dart:async";

import "package:flutter/foundation.dart";

import "../../data/local_audio_scanner.dart";
import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";

/// 本地扫描阶段（UI 阶段条/完成态共用）
enum LocalScanPhase { idle, scanning, syncing, done, failed }

/// 本地扫描状态机：消费扫描器事件流、节流刷新、完成后写库。
/// 扫描 UI 只读这里的状态，不直接碰 isolate / 数据库。
class LocalScanController extends ChangeNotifier {
  LocalScanController({
    LocalScanTask Function()? taskFactory,
    Future<void> Function(List<Track> tracks)? syncTracks,
  })  : _taskFactory = taskFactory ?? scanLocalLibraryTask,
        _syncTracks = syncTracks;

  final LocalScanTask Function() _taskFactory;
  final Future<void> Function(List<Track> tracks)? _syncTracks;

  LocalScanPhase phase = LocalScanPhase.idle;
  int scanned = 0;
  int indexed = 0;
  int failed = 0;
  String? error;

  /// 最近遍历到的文件完整路径（最多 12 条）
  final List<String> recentPaths = [];

  /// 失败文件（扫描完成后用于居中弹窗）
  final List<ScanFailure> failures = [];

  LocalScanTask? _task;
  StreamSubscription<LocalScanEvent>? _sub;
  Completer<void>? _done;
  Timer? _notifyTimer;
  bool _cancelled = false;
  bool _disposed = false;

  bool get cancelled => _cancelled;

  bool get canCancel => phase == LocalScanPhase.scanning;

  /// 开始扫描；返回时扫描/写库已结束（取消则提前返回）
  Future<void> start() async {
    if (phase != LocalScanPhase.idle) return;
    _cancelled = false;
    phase = LocalScanPhase.scanning;
    scanned = 0;
    indexed = 0;
    failed = 0;
    recentPaths.clear();
    failures.clear();
    error = null;
    _notifyNow();

    _done = Completer<void>();
    try {
      _task = _taskFactory();
      _sub = _task!.events.listen(
        _onEvent,
        onError: (Object e, StackTrace _) {
          error = e.toString();
          if (phase == LocalScanPhase.scanning) phase = LocalScanPhase.failed;
          _completeDone();
          _notifyNow();
        },
        // 正常完成由 _finish 的 finally 收尾；流提前关闭且未收到 done 视为失败
        onDone: () {
          if (phase == LocalScanPhase.scanning) {
            error ??= "扫描流提前结束";
            phase = LocalScanPhase.failed;
            _completeDone();
            _notifyNow();
          }
        },
      );
    } catch (e) {
      error = e.toString();
      phase = LocalScanPhase.failed;
      _completeDone();
      _notifyNow();
    }
    await _done!.future;
    _notifyNow();
  }

  void _onEvent(LocalScanEvent event) {
    if (_cancelled || _disposed) return;
    switch (event) {
      case LocalScanFiles(:final paths):
        recentPaths.addAll(paths);
        if (recentPaths.length > 12) {
          recentPaths.removeRange(0, recentPaths.length - 12);
        }
        _scheduleNotify();
      case LocalScanProgress(:final scanned, :final indexed, :final failed):
        this.scanned = scanned;
        this.indexed = indexed;
        this.failed = failed;
        _scheduleNotify();
      case LocalScanFileFailure(:final path, :final reason):
        failures.add(ScanFailure(path: path, reason: reason));
        _scheduleNotify();
      case LocalScanDone(:final result):
        unawaited(_finish(result));
    }
  }

  Future<void> _finish(LocalScanResult result) async {
    if (_cancelled || _disposed) {
      _completeDone();
      return;
    }
    phase = LocalScanPhase.syncing;
    _notifyNow();
    try {
      if (_syncTracks != null) {
        await _syncTracks(result.tracks);
      } else {
        await TrackRepository().syncLocalTracks(result.tracks,
          scannedRoots: result.roots.isEmpty ? null : result.roots,
          retainedPaths: result.failed,
          removeMissing: result.inaccessibleDirectories.isEmpty,
        );
      }
      if (_cancelled || _disposed) {
        _completeDone();
        return;
      }
      // 旧测试/旧 override 可能只填 failed，这里补一个通用原因
      final resultFailures = result.failures.isNotEmpty
          ? result.failures
          : [
              for (final path in result.failed)
                ScanFailure(path: path, reason: "读取失败"),
            ];
      failures
        ..clear()
        ..addAll(resultFailures);
      indexed = result.tracks.length;
      failed = failures.length;
      phase = LocalScanPhase.done;
      _notifyNow();
    } catch (e) {
      error = e.toString();
      phase = LocalScanPhase.failed;
      _notifyNow();
    } finally {
      _completeDone();
    }
  }

  /// 取消只在扫描阶段有效；进入写库阶段后等待事务完成
  void cancel() {
    if (!canCancel) return;
    _cancelled = true;
    _sub?.cancel();
    _sub = null;
    _task?.cancel();
    _task = null;
    phase = LocalScanPhase.idle;
    recentPaths.clear();
    _completeDone();
    _notifyNow();
  }

  void reset() {
    if (_disposed) return;
    phase = LocalScanPhase.idle;
    scanned = 0;
    indexed = 0;
    failed = 0;
    recentPaths.clear();
    failures.clear();
    error = null;
    _notifyNow();
  }

  void _completeDone() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 70), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _sub?.cancel();
    _task?.cancel();
    _completeDone();
    super.dispose();
  }
}
