import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/skeleton.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/playlist.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../player/mini_player_bar.dart";
import "../player/player_card_page.dart";
import "../playlist/playlists_provider.dart"
    show playlistDetailTracksProvider, queueTracksProvider;

/// 合集详情（对齐原型 renderSub/collection；S3.3 接真数据）
class CollectionDetailPage extends ConsumerWidget {
  final Playlist collection;

  const CollectionDetailPage({super.key, required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final tracksAsync = ref.watch(playlistDetailTracksProvider(collection));

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            // 空态走覆盖层（Stack + Positioned.fill）：居中于列表可视区且不占列表流
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BackLink(),
                    ),
                    // 头部：64px 封面 + 标题/副题（原型 23px 标题）
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: const Alignment(-0.64, -0.77),
                              end: const Alignment(0.64, 0.77),
                              colors: coverGradientColors(
                                collection.coverHue ?? 212,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                collection.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 23,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: t.fg,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "收藏 · ${tracksAsync.value?.length ?? collection.count} 首",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: t.fgDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 操作 chips（原型 .chip：播放全部选中态 + 加入待播放）
                    Row(
                      children: [
                        GlassChip(
                          label: "播放全部",
                          selected: true,
                          onTap: () => AppToast.show(context, "播放内核在 S4 接入"),
                        ),
                        const SizedBox(width: 10),
                        GlassChip(
                          label: "加入待播放",
                          onTap: () async {
                            final tracks = tracksAsync.value ?? const [];
                            for (final track in tracks) {
                              await TrackRepository().upsert(track);
                            }
                            await QueueRepository()
                                .replaceAll(tracks.map((t) => t.id).toList());
                            ref.invalidate(queueTracksProvider);
                            if (context.mounted) {
                              AppToast.show(context, "已加入播放队列");
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    tracksAsync.when(
                      loading: () => const SkeletonListView(rows: 6),
                      error: (e, _) => EmptyState(
                        compact: true,
                        emoji: "⚠️",
                        title: "加载失败",
                        subtitle: "点击重试",
                        action: GlassChip(
                          label: "重试",
                          onTap: () => ref.invalidate(
                            playlistDetailTracksProvider(collection),
                          ),
                        ),
                      ),
                      data: (tracks) => tracks.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              children: [
                                for (final track in tracks)
                                  SongListTile(
                                    track: track,
                                    onTap: () => PlayerCardPage.start(
                                      context,
                                      ref,
                                      track,
                                    ),
                                    onMorePressed: () => AppSheet.show(
                                      context,
                                      title: track.name,
                                      actions: [
                                        AppSheetAction(
                                          icon: Icons.queue_music_outlined,
                                          label: "下一首播放",
                                          onTap: () async {
                                            await TrackRepository()
                                                .upsert(track);
                                            await QueueRepository().insertNext(
                                              track.id,
                                              atPosition: 0,
                                            );
                                            ref.invalidate(queueTracksProvider);
                                          },
                                        ),
                                        AppSheetAction(
                                          icon: Icons.playlist_add,
                                          label: "加入待播放",
                                          onTap: () async {
                                            await TrackRepository()
                                                .upsert(track);
                                            await QueueRepository()
                                                .append(track.id);
                                            ref.invalidate(queueTracksProvider);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
                if (tracksAsync.hasValue && tracksAsync.value!.isEmpty)
                  const Positioned.fill(
                    child: EmptyState(
                      emoji: "🎵",
                      title: "合集还没有内容",
                      subtitle: "下拉刷新试试",
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
