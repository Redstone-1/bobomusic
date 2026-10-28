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

/// 广场页：搜索入口 + 榜单 TabBar + TabBarView 榜单列表
/// 热歌榜 = 酷我 SSR 真榜；其余为主题卡（多榜单接口已封死，见 kuwo_api 注释）
class PlazaPage extends ConsumerStatefulWidget {
  const PlazaPage({super.key});

  @override
  ConsumerState<PlazaPage> createState() => _PlazaPageState();
}

class _PlazaPageState extends ConsumerState<PlazaPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: plazaChartDefs.length,
    vsync: this,
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(title: "音乐广场", subtitle: "酷我榜单 · 发现好歌"),
              const SizedBox(height: 16),
              _SearchEntry(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
              ),
              const SizedBox(height: 10),
              // 榜单 Tab（family provider 各榜独立缓存，切换零等待）。
              // 无指示条；labelPadding 收紧后四榜 390dp 内左对齐放得下，不出横向滚动
              Theme(
                data: Theme.of(context).copyWith(
                  splashFactory: NoSplash.splashFactory,
                ),
                child: TabBar(
                  controller: _tab,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicator: const BoxDecoration(),
                  labelColor: t.primary,
                  unselectedLabelColor: t.fgMute,
                  dividerColor: Colors.transparent,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    for (final (_, name) in plazaChartDefs) Tab(text: name),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              for (final (key, name) in plazaChartDefs)
                _ChartListView(chartKey: key, chartName: name),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单榜列表（TabBarView 子页）：整包操作 + 排名歌曲行；keepAlive 保滚动位置
class _ChartListView extends ConsumerStatefulWidget {
  final String chartKey;
  final String chartName;

  const _ChartListView({
    required this.chartKey,
    required this.chartName,
  });

  @override
  ConsumerState<_ChartListView> createState() => _ChartListViewState();
}

class _ChartListViewState extends ConsumerState<_ChartListView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final chartAsync = ref.watch(kuwoChartProvider(widget.chartKey));
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 150),
      children: [
        chartAsync.when(
          loading: () => const SkeletonListView(rows: 8),
          error: (e, _) => EmptyState(
            compact: true,
            asset: "assets/illustrations/empty_alert.svg",
            title: "榜单加载失败",
            subtitle: "检查网络后重试",
            action: GlassChip(
              label: "重试",
              onTap: () =>
                  ref.invalidate(kuwoChartProvider(widget.chartKey)),
            ),
          ),
          data: (chart) => chart.hits.isEmpty
              ? const EmptyState(
                  compact: true,
                  asset: "assets/illustrations/empty_music.svg",
                  title: "榜单暂时没有数据",
                  subtitle: "稍后再试试",
                )
              : Column(
                  children: [
                    for (final (i, hit) in chart.hits.indexed)
                      _ChartSongRow(
                        rank: i + 1,
                        hit: hit,
                        playing: currentTrackId != null &&
                            hit.item?.id == currentTrackId,
                        onTap: () => _playHit(hit),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 单曲点播：解析 rid → 入库 → 开播（单曲会话，与旧热歌行一致）
  Future<void> _playHit(KuwoHotHit hit) async {
    final needsMatch = hit.item == null;
    if (needsMatch) AppLoading.show(msg: "匹配歌曲…");
    try {
      final track = await resolveKuwoHotHit(hit);
      if (!mounted) return;
      if (track == null) {
        AppToast.show(context, "未找到可播放的匹配版本");
        return;
      }
      await TrackRepository().upsert(track);
      if (!mounted) return;
      PlayerCardPage.start(context, ref, track);
    } finally {
      if (needsMatch) AppLoading.dismiss();
    }
  }
}

/// 榜单歌曲行：排名 + 封面 + 歌名/歌手 + 播放态（原热歌榜列表行样式）
class _ChartSongRow extends StatelessWidget {
  final int rank;
  final KuwoHotHit hit;
  final bool playing;
  final VoidCallback onTap;

  const _ChartSongRow({
    required this.rank,
    required this.hit,
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

/// 搜索入口（玻璃底 + 发现提示）
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
