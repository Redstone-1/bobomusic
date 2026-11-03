import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "playlists_provider.dart";

/// 侧栏和歌单页共用创建校验及错误出口，避免桌面入口绕过歌单数量限制。
Future<void> createPlaylist(BuildContext context, WidgetRef ref) async {
  try {
    final playlists = await ref.read(playlistsProvider.future);
    if (!context.mounted) return;
    if (playlists.length >= 20) {
      AppToast.show(context, "最多创建 20 个歌单");
      return;
    }
    final name = await AppDialog.input(context,
        title: "新建歌单", hint: "歌单名（1~20 字）", validator: (value) {
        final text = value?.trim() ?? "";
      if (text.isEmpty || text.length > 20) return "歌单名须为 1~20 字";
      return null;
    });
    if (name == null || !context.mounted) return;
    await ref.read(playlistsProvider.notifier).create(name.trim());
    if (context.mounted) AppToast.show(context, "已创建「${name.trim()}」");
  } catch (error) {
    print("创建歌单失败：$error");
    if (context.mounted) AppToast.show(context, "创建失败，请检查歌单名是否重复");
  }
}
