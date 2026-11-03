import "dart:async";

import "package:dio/dio.dart";
import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "download_service.dart";

part "download_tasks.g.dart";

enum DownloadTaskStatus { queued, downloading, paused, completed, failed }

class DownloadTask {
  final Track track;
  final DownloadTaskStatus status;
  final double progress;
  final String? message;
  const DownloadTask(
      {required this.track,
      required this.status,
      this.progress = 0,
      this.message});
  bool get active =>
      status == DownloadTaskStatus.queued ||
      status == DownloadTaskStatus.downloading;
  DownloadTask copyWith(
          {DownloadTaskStatus? status, double? progress, String? message}) =>
      DownloadTask(
          track: track,
          status: status ?? this.status,
          progress: progress ?? this.progress,
          message: message ?? this.message);
}

class _DownloadRun {
  final token = CancelToken();
  final done = Completer<void>();
}

@riverpod
Future<List<Track>> downloadedTracks(Ref ref) async =>
    TrackRepository().downloadedTracks();

/// 同曲目的旧写入与清理结束后才能开始新传输；迟到回调不复活已取消任务。
@Riverpod(keepAlive: true)
class DownloadTasks extends _$DownloadTasks {
  final _runs = <String, _DownloadRun>{};

  @override
  List<DownloadTask> build() {
    ref.onDispose(() {
      for (final run in _runs.values) {
        run.token.cancel("pause");
      }
    });
    return const [];
  }

  Future<DownloadResult> start(Track track) async {
    final previous = _runs[track.id];
    if (previous != null) {
      if (!previous.token.isCancelled) {
        return const DownloadResult(DownloadStatus.already, "正在下载，请稍候");
      }
      await previous.done.future;
    }
    if (!ref.mounted) {
      return const DownloadResult(DownloadStatus.failed, "下载已结束",
          interrupted: true);
    }
    // 多次继续可能同时等待旧任务，只允许其中一次取得写入权。
    if (_runs.containsKey(track.id)) {
      return const DownloadResult(DownloadStatus.already, "正在下载，请稍候");
    }
    final run = _DownloadRun();
    _runs[track.id] = run;
    _put(DownloadTask(track: track, status: DownloadTaskStatus.downloading));
    DownloadResult result;
    try {
      result = await downloadService.download(track, cancelToken: run.token,
          onProgress: (progress) {
        if (!ref.mounted || run.token.isCancelled || _runs[track.id] != run) {
          return;
        }
        _put(DownloadTask(
            track: track,
            status: DownloadTaskStatus.downloading,
            progress: progress.clamp(0.0, 1.0)));
      });
      if (ref.mounted &&
          _runs[track.id] == run &&
          run.token.cancelError?.error != "cancel") {
        if (result.ok) {
          _put(DownloadTask(
              track: track,
              status: DownloadTaskStatus.completed,
              progress: 1,
              message: result.message));
          ref.invalidate(downloadedTracksProvider);
        } else if (!result.interrupted) {
          _put(DownloadTask(
              track: track,
              status: DownloadTaskStatus.failed,
              message: result.message));
        }
      }
    } catch (e) {
      result = DownloadResult(DownloadStatus.failed, "下载失败：$e",
          interrupted: run.token.isCancelled);
      if (ref.mounted && !run.token.isCancelled) {
        _put(DownloadTask(
            track: track,
            status: DownloadTaskStatus.failed,
            message: result.message));
      }
    } finally {
      try {
        if (run.token.cancelError?.error == "cancel") {
          await downloadService.discardPartial(track);
        }
      } catch (e) {
        print("取消下载清理失败：$e");
      }
      if (_runs[track.id] == run) _runs.remove(track.id);
      run.done.complete();
    }
    return result;
  }

  Future<void> pause(String trackId) async {
    final run = _runs[trackId];
    if (run == null || run.token.isCancelled) return;
    run.token.cancel("pause");
    state = [
      for (final task in state)
        task.track.id == trackId
            ? task.copyWith(status: DownloadTaskStatus.paused)
            : task
    ];
    await run.done.future;
  }

  Future<void> cancel(Track track) async {
    var run = _runs[track.id];
    if (run != null && run.token.isCancelled) {
      // 暂停操作正在释放句柄时，等待它结束后再独占清理，避免续传与清理并发。
      await run.done.future;
      if (!ref.mounted) return;
      return cancel(track);
    }
    if (run != null) {
      run.token.cancel("cancel");
      remove(track.id);
      await run.done.future;
      return;
    }
    run = _DownloadRun()..token.cancel("cancel");
    _runs[track.id] = run;
    remove(track.id);
    try {
      await downloadService.discardPartial(track);
    } catch (e) {
      print("取消下载清理失败：$e");
    } finally {
      if (_runs[track.id] == run) _runs.remove(track.id);
      run.done.complete();
    }
  }

  Future<void> retry(Track track) async {
    await start(track);
  }

  void remove(String trackId) {
    state = [
      for (final task in state)
        if (task.track.id != trackId) task
    ];
  }

  void clearFinished() {
    state = [
      for (final task in state)
        if (task.status != DownloadTaskStatus.completed) task
    ];
  }

  void _put(DownloadTask task) {
    final next = [...state];
    final index = next.indexWhere((item) => item.track.id == task.track.id);
    if (index < 0) {
      next.add(task);
    } else {
      next[index] = task;
    }
    state = List.unmodifiable(next);
  }
}
