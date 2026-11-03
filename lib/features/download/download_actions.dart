import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_toast.dart";
import "../../data/models/track.dart";
import "download_tasks.dart";

/// 下载入口（播放卡动作行 / 歌曲菜单共用）：任务层统一维护进度 + 结果提示
Future<void> downloadTrack(BuildContext context, Track track) async {
  if (track.origin == OriginType.local) {
    AppToast.show(context, "本地音乐无需下载");
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final future = container.read(downloadTasksProvider.notifier).start(track);
  AppToast.show(context, "已开始下载");
  // 失败时补一次提示；成功由下载管理页展示
  future.then((result) {
    if (!result.ok && !result.interrupted && context.mounted) {
      AppToast.show(context, result.message);
    }
  });
}
