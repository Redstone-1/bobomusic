import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_form_field.dart";
import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "display_edit_actions.dart";

/// 编辑曲目显示信息：B 站等音源的标题/歌手由上传者自定义（长、奇葩名），
/// 封面可替换（URL，允许为空恢复原始）。原始 name/author/cover 保留——
/// 歌词匹配与下载文件名不受影响。保存后失效相关列表数据源（详情页保数据
/// 不塌缩）；正在播放的曲目热更新迷你条/播放卡/系统通知
Future<void> showTrackEditDialog(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final t = AuroraTokens.of(context);
  final nameController = TextEditingController(text: track.effectiveName);
  final authorController = TextEditingController(text: track.effectiveAuthor);
  final coverController = TextEditingController(text: track.effectiveCover);

  final ok = await AppDialog.show<bool>(
    context,
    title: "编辑歌曲信息",
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFormField(controller: nameController, label: "歌名"),
        const SizedBox(height: 10),
        AppFormField(controller: authorController, label: "歌手"),
        const SizedBox(height: 10),
        AppFormField(controller: coverController, label: "封面 URL"),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text("取消", style: TextStyle(color: t.fgDim)),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          "保存",
          style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
  if (ok != true) return;

  final name = nameController.text.trim();
  if (name.isEmpty) {
    if (context.mounted) AppToast.show(context, "歌名不能为空");
    return;
  }
  try {
    final displayActions = ref.read(trackDisplayActionsProvider);
    await TrackRepository().updateDisplayInfo(
      track.id,
      name: name,
      author: authorController.text.trim(),
      // 封面 URL 允许为空：留空 = 清除覆盖、恢复原始封面
      cover: coverController.text.trim(),
    );
    final refreshed = await displayActions.refresh([track.id]);
    if (context.mounted) {
      AppToast.show(context, refreshed ? "已保存" : "修改已保存，界面刷新失败，请稍后重试");
    }
  } catch (e) {
    print("保存歌曲信息失败：$e");
    if (context.mounted) AppToast.show(context, "保存失败，请重试");
  }
}
