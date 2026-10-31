import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "../download/download_tasks.dart";
import "../player/playback_provider.dart";
import "playlists_provider.dart"
    show
        playlistDetailTracksProvider,
        queueEntriesProvider,
        recentTracksProvider;

/// 编辑曲目显示信息：B 站等音源的标题/歌手由上传者自定义（长、奇葩名），
/// 支持本地覆盖显示。原始 name/author 保留——歌词匹配与下载文件名不受影响。
/// 保存后失效相关列表数据源（详情页保数据不塌缩）；正在播放的曲目热更新
/// 迷你条/播放卡/系统通知
Future<void> showTrackEditDialog(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final t = AuroraTokens.of(context);
  final nameController = TextEditingController(text: track.effectiveName);
  final authorController = TextEditingController(text: track.effectiveAuthor);

  final ok = await AppDialog.show<bool>(
    context,
    title: "编辑歌曲信息",
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(t, controller: nameController, label: "歌名"),
        const SizedBox(height: 10),
        _field(t, controller: authorController, label: "歌手"),
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
    await TrackRepository().updateDisplayInfo(
      track.id,
      name: name,
      author: authorController.text.trim(),
    );
    // 各列表数据源重读（详情页重读期间保留旧数据）；下载完成列表同步
    ref.invalidate(playlistDetailTracksProvider);
    ref.invalidate(queueEntriesProvider);
    ref.invalidate(recentTracksProvider);
    ref.invalidate(downloadedTracksProvider);
    // 正在播放/队列中引用了该曲：按库内最新 Track 热更新当前会话
    final playback = ref.read(playbackProvider);
    final inSession = playback.track?.id == track.id ||
        playback.queue.any((item) => item.id == track.id);
    if (inSession) {
      final stored = await TrackRepository().getById(track.id);
      if (stored != null) {
        ref.read(playbackProvider.notifier).applyDisplayEdit(stored);
      }
    }
    if (context.mounted) AppToast.show(context, "已保存");
  } catch (e) {
    print("保存歌曲信息失败：$e");
    if (context.mounted) AppToast.show(context, "保存失败，请重试");
  }
}

Widget _field(
  AuroraTokens t, {
  required TextEditingController controller,
  required String label,
}) {
  return TextField(
    controller: controller,
    style: TextStyle(fontSize: 14.5, color: t.fg),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: t.fgDim),
      filled: true,
      fillColor: t.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.primary),
      ),
    ),
  );
}
