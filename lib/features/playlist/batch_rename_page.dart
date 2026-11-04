import "batch_track_edit_page.dart";

/// 重命名入口沿用同一批量编辑页，预览、勾选、应用与撤销共用状态链。
class BatchRenamePage extends BatchTrackEditPage {
  const BatchRenamePage({super.key, required super.tracks})
      : super(mode: BatchTrackEditMode.rename);
}
