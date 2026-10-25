import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../data/models/playlist.dart";
import "../../data/models/track.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/track_repository.dart";
import "playlists_provider.dart"
    show playlistDetailTracksProvider, playlistsProvider;

/// 「加入歌单」面板：普通歌单禁止重复（§3.4-6），成功/重复都有提示
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final playlists = (await PlaylistRepository().list())
      .where((p) => p.type == PlaylistType.custom)
      .toList();
  if (!context.mounted) return;
  if (playlists.isEmpty) {
    AppToast.show(context, "还没有自定义歌单，请先在歌单页创建");
    return;
  }
  AppSheet.show(
    context,
    title: "加入歌单",
    actions: [
      for (final playlist in playlists)
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: playlist.name,
          onTap: () async {
            await TrackRepository().upsert(track);
            final added =
                await PlaylistRepository().addTrack(playlist.id, track.id);
            ref.invalidate(playlistsProvider);
            ref.invalidate(playlistDetailTracksProvider);
            if (context.mounted) {
              AppToast.show(
                context,
                added ? "已加入「${playlist.name}」" : "已在歌单中",
              );
            }
          },
        ),
    ],
  );
}
