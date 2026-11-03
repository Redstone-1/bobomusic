/// 音源类型（D11：歌曲条目与播放页显示音源标签）
enum OriginType { bili, kuwo, netease, qq, qianqian, local }

/// 曲目实体（mock 形状 = 重构计划 §3.1 tracks 表）
/// S3 起由 Repository 从真数据映射
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

  /// 歌词时间校准偏移（毫秒；正数 = 歌词延后显示）
  final int lyricOffsetMs;

  /// 显示用歌名覆盖（B 站等音源标题由上传者自定义，支持本地改名；
  /// null = 未改。原始 name/author 永不被覆盖，歌词匹配与下载文件名不受影响）
  final String? displayName;

  /// 显示用歌手覆盖（同上）
  final String? displayAuthor;

  /// 显示用封面覆盖（URL；null = 未改。原始 cover 保留，清空覆盖即恢复原始）
  final String? displayCover;

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
    this.lyricOffsetMs = 0,
    this.displayName,
    this.displayAuthor,
    this.displayCover,
  });

  /// 展示用歌名/歌手/封面（列表行、播放卡、媒体通知等 UI 消费；未改时回退原始值）。
  /// cover 本身可空（本地曲常无封面），effectiveCover 同为可空
  String get effectiveName => displayName ?? name;
  String get effectiveAuthor => displayAuthor ?? author;
  String? get effectiveCover => displayCover ?? cover;
}
