import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_loading.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/eq_bars.dart";
import "../../core/widgets/glass_card.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/skeleton.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/origin_types.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "hot_songs_provider.dart";
import "search_page.dart";

/// 广场页：搜索入口 + 酷我官方热歌榜（标题/歌手来自榜单，点播时解析 rid）
class PlazaPage extends ConsumerWidget {
  const PlazaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hotHitsAsync = ref.watch(kuwoHotHitsProvider);
    final hotHits = hotHitsAsync.value ?? const <KuwoHotHit>[];
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );

    Future<void> refreshHot() async {
      if (hotHitsAsync.isLoading) return;
      AppToast.show(context, "正在刷新热歌榜…");
      ref.invalidate(kuwoHotHitsProvider);
      try {
        final hits = await ref.read(kuwoHotHitsProvider.future);
        if (!context.mounted) return;
        AppToast.show(
          context,
          hits.isEmpty ? "暂无热歌数据" : "热歌榜已刷新",
        );
      } catch (_) {
        if (context.mounted) AppToast.show(context, "刷新失败，请检查网络");
      }
    }

    Future<void> playHit(KuwoHotHit hit) async {
      // 已带 SSR 结果的条目直接播放；只有需要匹配 rid 时才显示 loading，避免遮住迷你条
      final needsMatch = hit.item == null;
      if (needsMatch) AppLoading.show(msg: "匹配酷我热歌…");
      try {
        final track = await resolveKuwoHotHit(hit);
        if (!context.mounted) return;
        if (track == null) {
          AppToast.show(context, "未找到可播放的匹配版本");
          return;
        }
        await TrackRepository().upsert(track);
        if (!context.mounted) return;
        PlayerCardPage.start(context, ref, track);
      } finally {
        if (needsMatch) AppLoading.dismiss();
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
      children: [
        const PageHeader(title: "音乐广场", subtitle: "酷我热歌 · 发现好歌"),
        const SizedBox(height: 16),
        _SearchEntry(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
        ),
        // 酷我官方热歌榜：标题来自榜单页，点击时解析可播 rid
        if (hotHitsAsync.isLoading && hotHits.isEmpty) ...[
          const SectionHeader(title: "热门歌曲", trailing: "加载中"),
          const SkeletonListView(rows: 3),
        ] else if (hotHitsAsync.hasError && hotHits.isEmpty) ...[
          const SectionHeader(title: "热门歌曲"),
          EmptyState(
            compact: true,
            icon: Icons.cloud_off_outlined,
            title: "热歌榜加载失败",
            subtitle: "检查网络后重试",
            action: GlassChip(
              label: "重试",
              onTap: refreshHot,
            ),
          ),
        ] else if (hotHits.isNotEmpty) ...[
          const SizedBox(height: 18),
          _FeaturedSongCard(
            hit: hotHits.first,
            onTap: () => playHit(hotHits.first),
          ),
          SectionHeader(
            title: "热门歌曲",
            trailing: hotHitsAsync.isLoading ? "刷新中…" : "刷新",
            onTrailingTap: hotHitsAsync.isLoading ? null : refreshHot,
          ),
          for (final (i, hit) in hotHits.take(8).indexed)
            _HotSongRow(
              hit: hit,
              rank: i + 1,
              playing: currentTrackId != null &&
                  hit.item?.id == currentTrackId,
              onTap: () => playHit(hit),
            ),
        ],
      ],
    );
  }
}

/// 搜索入口（重设计后的主搜索条：玻璃底 + 发现提示）
class _SearchEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      pressedScale: 0.985,
      child: GlassCard(
        frosted: true,
        radius: t.radiusLg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: t.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "搜索歌曲 / 歌手 / 合集",
                style: TextStyle(fontSize: 14, color: t.fgDim),
              ),
            ),
            Icon(Icons.tune, size: 18, color: t.fgMute),
          ],
        ),
      ),
    );
  }
}

/// 官方热榜主卡：标题/歌手来自榜单，item 已解析时显示封面
class _FeaturedSongCard extends StatelessWidget {
  final KuwoHotHit hit;
  final VoidCallback onTap;

  const _FeaturedSongCard({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      pressedScale: 0.98,
      child: GlassCard(
        frosted: true,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CoverPlaceholder(
              cover: hit.item?.cover,
              text: hit.name,
              size: 92,
              radius: 18,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "酷我热歌榜",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hit.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hit.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.fgDim),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_fill, size: 18, color: t.primary),
                      const SizedBox(width: 5),
                      Text(
                        "立即播放",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 热门歌曲榜单行：排名 + 封面 + 歌名/歌手 + 播放态
class _HotSongRow extends StatelessWidget {
  final KuwoHotHit hit;
  final int rank;
  final bool playing;
  final VoidCallback onTap;

  const _HotSongRow({
    required this.hit,
    required this.rank,
    required this.playing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                "$rank",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? t.primary : t.fgMute,
                ),
              ),
            ),
            CoverPlaceholder(
              cover: hit.item?.cover,
              text: hit.name,
              size: 44,
              radius: t.radiusSm,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: playing ? t.primary : t.fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hit.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.fgDim),
                  ),
                ],
              ),
            ),
            if (playing) const EqBars(),
          ],
        ),
      ),
    );
  }
}
