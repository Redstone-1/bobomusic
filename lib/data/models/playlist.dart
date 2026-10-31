/// 歌单类型（§3.1 playlists.type）
enum PlaylistType { builtIn, custom, collection }

/// 内置「我喜欢」歌单：播放卡/搜索页的喜欢操作按此精确失效对应详情数据源
/// （family 相等性按 id，与歌单页/详情页构造的实例天然相等）
const Playlist kBuiltinLikedPlaylist = Playlist(
  id: "builtin:liked",
  name: "我喜欢",
  type: PlaylistType.builtIn,
);

/// 歌单元数据（mock 形状 = 重构计划 §3.1 playlists 表）
class Playlist {
  final String id;
  final String name;
  final PlaylistType type;
  final int count; // mock 用：曲目数（真数据由 playlist_items 聚合）

  const Playlist({
    required this.id,
    required this.name,
    required this.type,
    this.count = 0,
  });

  /// 相等性按 id（family provider 参数缓存与刷新依赖它）
  @override
  bool operator ==(Object other) => other is Playlist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
