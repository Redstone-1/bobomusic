import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/skeleton.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/playlist.dart";
import "../../data/models/track.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../player/mini_player_bar.dart";
import "../player/player_card_page.dart";

/// 歌单详情（对齐原型 renderSub/playlist）
/// 两种数据模式：
/// - [tracks] 非空：内存注入（热门歌手/合集等外部数据源）
/// - [tracks] 为空：按 [playlist] 从库取数（我喜欢 → likedTracks；本地 → localTracks；自定义 → items）
/// [trackCover] = 曲目行统一封面（如歌手歌单共用歌手写真），空则各行用自身封面
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final Playlist playlist;
  final List<Track>? tracks;
  final String? trackCover;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    this.tracks,
    this.trackCover,
  });

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  late Future<List<Track>> _future;
  int _reloadSeq = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Track>> _load() async {
    if (widget.tracks != null) return widget.tracks!;
    if (widget.playlist.id == "builtin:liked") {
      return TrackRepository().likedTracks();
    }
    if (widget.playlist.id == "builtin:local") {
      return TrackRepository().localTracks();
    }
    return PlaylistRepository().items(widget.playlist.id);
  }

  void _retry() {
    setState(() {
      _reloadSeq++;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              children: [
                const Align(alignment: Alignment.centerLeft, child: BackLink()),
                PageHeader(
                  title: widget.playlist.name,
                  subtitle: "播放全部",
                  trailing: GlassIconButton(
                    icon: const Icon(Icons.shuffle_outlined),
                    onTap: () {},
                  ),
                ),
                const SizedBox(height: 14),
                FutureBuilder(
                  key: ValueKey(_reloadSeq),
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const SkeletonListView(rows: 6);
                    }
                    if (snap.hasError) {
                      return EmptyState(
                        compact: true,
                        emoji: "⚠️",
                        title: "加载失败",
                        subtitle: "点击重试",
                        action: GlassChip(label: "重试", onTap: _retry),
                      );
                    }
                    final tracks = snap.data!;
                    if (tracks.isEmpty) {
                      return const EmptyState(
                        emoji: "🎵",
                        title: "歌单还是空的",
                        subtitle: "从广场搜索或本地扫描添加歌曲",
                      );
                    }
                    return Column(
                      children: [
                        for (final track in tracks)
                          SongListTile(
                            track: track,
                            coverOverride: widget.trackCover,
                            onTap: () =>
                                PlayerCardPage.start(context, ref, track),
                            onMorePressed: () => AppSheet.show(
                              context,
                              title: track.name,
                              actions: [
                                AppSheetAction(
                                  icon: Icons.queue_music_outlined,
                                  label: "下一首播放",
                                  onTap: () {},
                                ),
                                AppSheetAction(
                                  icon: Icons.playlist_add,
                                  label: "加入待播放",
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                SizedBox(height: t.radiusLg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
