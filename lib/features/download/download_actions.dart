import "package:flutter/material.dart";

import "../../core/overlays/app_loading.dart";
import "../../core/overlays/app_toast.dart";
import "../../data/models/track.dart";
import "download_service.dart";

/// 下载入口（播放卡动作行 / 歌曲菜单共用）：加载态 + 结果提示
Future<void> downloadTrack(BuildContext context, Track track) async {
  if (track.origin == OriginType.local) {
    AppToast.show(context, "本地音乐无需下载");
    return;
  }
  AppLoading.show(msg: "下载中…");
  late final DownloadResult result;
  try {
    result = await downloadService.download(track);
  } finally {
    AppLoading.dismiss();
  }
  if (!context.mounted) return;
  AppToast.show(context, result.message);
}
