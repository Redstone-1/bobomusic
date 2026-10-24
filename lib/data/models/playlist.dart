/// 歌单类型（§3.1 playlists.type）
enum PlaylistType { builtIn, custom, collection }

/// 歌单元数据（mock 形状 = 重构计划 §3.1 playlists 表）
class Playlist {
  final String id;
  final String name;
  final PlaylistType type;
  final int count; // mock 用：曲目数（真数据由 playlist_items 聚合）

  /// 仅 mock 用：占位封面色相
  final int? coverHue;

  const Playlist({
    required this.id,
    required this.name,
    required this.type,
    this.count = 0,
    this.coverHue,
  });
}
