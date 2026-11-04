import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../data/models/playlist.dart";
import "../../data/models/track.dart";
import "../../data/models/queue_entry.dart";
import "../../data/repositories/history_repository.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";

part "playlists_provider.g.dart";

/// 歌单目录（歌单页真数据源）：加载 + CRUD（每次变更后重载目录）
@riverpod
class Playlists extends _$Playlists {
  @override
  Future<List<Playlist>> build() => _load();

  Future<List<Playlist>> _load() async =>
      (await PlaylistRepository().list())
          .where((p) => p.type == PlaylistType.custom)
          .toList();

  /// 新建歌单；重名抛异常由 UI 提示
  Future<void> create(String name) async {
    await PlaylistRepository().create(name);
    ref.invalidateSelf();
  }

  Future<void> rename(String playlistId, String name) async {
    await PlaylistRepository().rename(int.parse(playlistId), name);
    ref.invalidateSelf();
  }

  Future<List<String>> updateInfo(String playlistId, {
    required String name,
    String? customCover,
    bool applyCoverToTracks = false,
  }) async {
    final changedIds = await PlaylistRepository().updateInfo(playlistId, name: name,
        customCover: customCover, applyCoverToTracks: applyCoverToTracks);
    // 详情 family 依赖目录，随目录刷新即可；不能在这里反向失效详情形成循环。
    ref.invalidateSelf();
    return changedIds;
  }

  Future<void> remove(String playlistId) async {
    await PlaylistRepository().delete(int.parse(playlistId));
    ref.invalidateSelf();
  }

  void refresh() => ref.invalidateSelf();
}

/// 详情按 ID 订阅最新元数据，编辑名称/封面后不再依赖导航时的快照。
@riverpod
Future<Playlist?> playlistInfo(Ref ref, String playlistId) async {
  // 成员增删也会刷新目录；复用同一份元数据，详情封面和数量随之更新。
  final playlists = await ref.watch(playlistsProvider.future);
  for (final playlist in playlists) {
    if (playlist.id == playlistId) return playlist;
  }
  return null;
}

/// 我喜欢数量（快捷卡计数）
@riverpod
Future<int> likedCount(Ref ref) async =>
    (await TrackRepository().likedTracks()).length;

/// 本地音乐数量（快捷卡计数；C3 本地扫描后填充）
@riverpod
Future<int> localCount(Ref ref) async => TrackRepository().localCount();

/// 独立待播条目；所有写队列入口统一刷新此 provider。
@riverpod
Future<List<QueueEntry>> queueEntries(Ref ref) async =>
    QueueRepository().entries();

/// 最近播放（歌单页；切歌后由页面 invalidate）
@riverpod
Future<List<Track>> recentTracks(Ref ref) async => HistoryRepository().recent();

/// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）
@riverpod
Future<List<Track>> playlistDetailTracks(Ref ref, String playlistId) async {
  if (playlistId == "builtin:liked") return TrackRepository().likedTracks();
  if (playlistId == "builtin:local") return TrackRepository().localTracks();
  return PlaylistRepository().items(playlistId);
}
