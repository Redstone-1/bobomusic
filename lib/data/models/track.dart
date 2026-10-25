/// 音源类型（D11：歌曲条目与播放页显示音源标签）
enum OriginType { bili, kuwo, local }

/// 曲目实体（mock 形状 = 重构计划 §3.1 tracks 表）
/// S3 起由 Repository 从真数据映射；[coverHue] 仅为 mock 占位封面保留
class Track {
  final String id;
  final String name;
  final String author;
  final String? cover;
  final int? duration; // 秒
  final OriginType origin;
  final bool liked;

  /// 本地文件路径（本地音乐/已下载，§3.4-8）
  final String? localPath;

  /// 歌词 LRC 原文（属于曲目，§3.4-7 全局共享）
  final String? lyric;

  /// 仅 mock 用：占位封面色相（真实数据用 cover 图链）
  final int? coverHue;

  const Track({
    required this.id,
    required this.name,
    required this.author,
    this.cover,
    this.duration,
    this.origin = OriginType.bili,
    this.liked = false,
    this.localPath,
    this.lyric,
    this.coverHue,
  });
}
