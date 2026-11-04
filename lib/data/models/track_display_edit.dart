import "track.dart";

/// 只更新用户选定的显示字段；null 可用于撤销覆盖，其余字段保持原样。
class TrackDisplayEdit {
  const TrackDisplayEdit({
    required this.trackId,
    this.name,
    this.author,
    this.cover,
    this.updateName = false,
    this.updateAuthor = false,
    this.updateCover = false,
    this.validateOnly = false,
    this.expected,
  });

  final String trackId;
  final String? name;
  final String? author;
  final String? cover;
  final bool updateName;
  final bool updateAuthor;
  final bool updateCover;

  /// 已勾选但预览值未变化时，仍校验目标字段，不写覆盖值或生成撤销项。
  final bool validateOnly;

  /// 预览及撤销都校验涉及的旧字段，防止覆盖预览后发生的手动编辑。
  final Track? expected;
}
