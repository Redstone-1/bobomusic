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

/// 「加入歌单」面板：普通歌单禁止重复（§3.4-6）；[tracks] 支持多首批量
/// （合集整包加入），成功/重复都有提示
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
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
            var added = 0;
            for (final track in tracks) {
              await TrackRepository().upsert(track);
              if (await PlaylistRepository().addTrack(playlist.id, track.id)) {
                added++;
              }
            }
            ref.invalidate(playlistsProvider);
            // 精确失效目标歌单详情数据源，不殃及打开中的其它详情页
            ref.invalidate(playlistDetailTracksProvider(playlist.id));
            if (context.mounted) {
              final total = tracks.length;
              final String message;
              if (added == 0) {
                message = "歌曲均已在歌单中";
              } else if (total == 1) {
                message = "已加入「${playlist.name}」";
              } else if (added == total) {
                message = "已加入「${playlist.name}」$total 首";
              } else {
                message = "已加入「${playlist.name}」$added 首，"
                    "${total - added} 首已在歌单中";
              }
              AppToast.show(context, message);
            }
          },
        ),
    ],
  );
}
