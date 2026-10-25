import "package:flutter/material.dart";

import "../../core/overlays/app_toast.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/mock/mock_data.dart";
import "../../data/models/playlist.dart";
import "../../data/models/track.dart";

/// 歌单详情（对齐原型 renderSub/playlist）
/// mock 阶段曲目列表由调用方注入；S3 改为按 playlist.id 从 Repository 取数，UI 不动
class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;
  final List<Track> tracks;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    this.tracks = mockTracks,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const Align(alignment: Alignment.centerLeft, child: BackLink()),
              PageHeader(
                title: playlist.name,
                subtitle: "${tracks.length} 首 · 播放全部",
                trailing: GlassIconButton(
                  icon: const Icon(Icons.shuffle_outlined),
                  onTap: () => AppToast.show(context, "播放内核在 S4 接入"),
                ),
              ),
              const SizedBox(height: 14),
              for (final track in tracks)
                SongListTile(
                  track: track,
                  onTap: () => AppToast.show(context, "播放内核在 S4 接入"),
                  onMorePressed: () =>
                      AppToast.show(context, "播放队列在批次 3/4 提供"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
