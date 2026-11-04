import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/models/track_display_edit.dart";
import "../../data/repositories/track_repository.dart";
import "../download/download_tasks.dart";
import "../player/playback_provider.dart";
import "playlists_provider.dart";

/// 普通 Provider 随应用容器存活，写入的收尾不依赖发起页面是否还在。
final trackDisplayActionsProvider = Provider<TrackDisplayActions>(
  (ref) => TrackDisplayActions(ref),
);

class DisplayEditResult {
  const DisplayEditResult({required this.undo, required this.refreshed});

  final List<TrackDisplayEdit> undo;
  final bool refreshed;
}

class TrackDisplayActions {
  TrackDisplayActions(this._ref);

  final Ref _ref;

  Future<DisplayEditResult> apply(List<TrackDisplayEdit> edits) async {
    // 只有事务失败才抛出保存错误；提交后读取失败不代表写入已回滚。
    final undo = await TrackRepository().updateDisplayBatch(edits);
    final refreshed = await refresh(edits.map((edit) => edit.trackId));
    return DisplayEditResult(undo: undo, refreshed: refreshed);
  }

  Future<bool> refresh(Iterable<String> ids) async {
    if (!_ref.mounted) return false;
    try {
      // 即使后续读取失败，其他列表也应先失效，重新进入时能拿到已提交的数据。
      _ref.invalidate(playlistDetailTracksProvider);
      _ref.invalidate(playlistsProvider);
      _ref.invalidate(queueEntriesProvider);
      _ref.invalidate(recentTracksProvider);
      _ref.invalidate(downloadedTracksProvider);
      // 读取整批而非提前截取会话，查询期间切歌也能拿到该曲的新信息。
      final stored = await TrackRepository().getByIds(ids.toSet().toList());
      if (!_ref.mounted) return false;
      _ref.read(playbackProvider.notifier).applyDisplayEdits(stored);
      return true;
    } catch (error) {
      print("歌曲信息已保存，刷新显示失败：$error");
      return false;
    }
  }
}
