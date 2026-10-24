/// 音源类型（D11：歌曲条目与播放页显示音源标签）
enum OriginType { bili, kuwo, local }

/// 曲目实体（mock 形状 = 重构计划 §3.1 tracks 表）
/// S1 阶段为纯 mock 数据类；S3 接真数据时按 Repository 返回值机械替换
class Track {
  final String id;
  final String name;
  final String author;
  final String? cover;
  final int? duration; // 秒
  final OriginType origin;
  final bool liked;

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
    this.coverHue,
  });
}
