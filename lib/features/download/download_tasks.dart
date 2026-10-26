import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "download_service.dart";

part "download_tasks.g.dart";

enum DownloadTaskStatus { queued, downloading, completed, failed }

class DownloadTask {
  final Track track;
  final DownloadTaskStatus status;
  final double progress;
  final String? message;

  const DownloadTask({
    required this.track,
    required this.status,
    this.progress = 0,
    this.message,
  });

  bool get active =>
      status == DownloadTaskStatus.queued ||
      status == DownloadTaskStatus.downloading;

  DownloadTask copyWith({
    DownloadTaskStatus? status,
    double? progress,
    String? message,
  }) =>
      DownloadTask(
        track: track,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        message: message ?? this.message,
      );
}

/// 已下载列表（数据源 = tracks.downloaded_at；下载完成后由任务层失效）
@riverpod
Future<List<Track>> downloadedTracks(Ref ref) async =>
    TrackRepository().downloadedTracks();

/// 下载任务（内存态，显示在下载管理页的「下载中」）
/// keepAlive：下载在后台进行，页面关闭任务列表不能随之销毁
@Riverpod(keepAlive: true)
class DownloadTasks extends _$DownloadTasks {
  @override
  List<DownloadTask> build() => const [];

  /// 开始下载；同一曲目正在下载时不重复启动
  Future<DownloadResult> start(Track track) async {
    final running = state.any(
      (task) => task.track.id == track.id && task.active,
    );
    if (running) {
      return const DownloadResult(DownloadStatus.already, "正在下载，请稍候");
    }

    _put(
      DownloadTask(
        track: track,
        status: DownloadTaskStatus.downloading,
      ),
    );

    DownloadResult result;
    try {
      result = await downloadService.download(
        track,
        onProgress: (progress) {
          _put(
            DownloadTask(
              track: track,
              status: DownloadTaskStatus.downloading,
              progress: progress.clamp(0.0, 1.0).toDouble(),
            ),
          );
        },
      );
    } catch (e) {
      result = DownloadResult(DownloadStatus.failed, "下载失败：$e");
    }

    if (result.ok) {
      _put(
        DownloadTask(
          track: track,
          status: DownloadTaskStatus.completed,
          progress: 1,
          message: result.message,
        ),
      );
      ref.invalidate(downloadedTracksProvider);
    } else {
      _put(
        DownloadTask(
          track: track,
          status: DownloadTaskStatus.failed,
          message: result.message,
        ),
      );
    }
    return result;
  }

  Future<void> retry(Track track) async {
    await start(track);
  }

  void remove(String trackId) {
    state = [
      for (final task in state)
        if (task.track.id != trackId) task,
    ];
  }

  void clearFinished() {
    state = [
      for (final task in state)
        if (task.active || task.status == DownloadTaskStatus.failed) task,
    ];
  }

  void _put(DownloadTask task) {
    final next = [...state];
    final index = next.indexWhere((t) => t.track.id == task.track.id);
    if (index < 0) {
      next.add(task);
    } else {
      next[index] = task;
    }
    state = List.unmodifiable(next);
  }
}
