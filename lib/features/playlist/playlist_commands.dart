import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/navigation/desktop_navigation.dart";
import "../../core/widgets/desktop_content.dart";
import "../../data/models/playlist.dart";
import "../../data/playlist_cover_store.dart";
import "playlist_detail_page.dart";
import "playlist_edit_dialog.dart";
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

void openPlaylist(BuildContext context, WidgetRef ref, Playlist playlist) {
  if (DesktopContent.of(context)) {
    ref.read(desktopNavigationProvider.notifier).open(
        DesktopDestination("playlist", playlist.name, playlistId: playlist.id));
  } else {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaylistDetailPage(playlist: playlist)));
  }
}

/// 首页和全部歌单页共用菜单，编辑与删除的行为始终一致。
void showPlaylistActions(BuildContext context, WidgetRef ref, Playlist playlist) {
  AppSheet.show(context, actions: [
    AppSheetAction(icon: Icons.edit_outlined, label: "编辑信息",
        onTap: () => showPlaylistEditDialog(context, ref, playlist)),
    AppSheetAction(icon: Icons.delete_outline, label: "删除歌单", danger: true,
        onTap: () async {
          final ok = await AppDialog.confirm(context, title: "删除歌单",
              message: "歌单「${playlist.name}」将被删除，歌曲不受影响。",
              danger: true, confirmText: "删除");
          if (!ok || !context.mounted) return;
          try {
            await ref.read(playlistsProvider.notifier).remove(playlist.id);
            await PlaylistCoverStore().removeIfUnused(playlist.customCover);
            if (context.mounted) AppToast.show(context, "已删除");
          } catch (error) {
            print("删除歌单失败：$error");
            if (context.mounted) AppToast.show(context, "删除失败，请重试");
          }
        }),
  ]);
}
