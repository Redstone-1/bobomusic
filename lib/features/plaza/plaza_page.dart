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
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/skeleton.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/origin_types.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "hot_songs_provider.dart";
import "search_page.dart";

/// 广场页：搜索入口 + 榜单 TabBar + TabBarView 榜单列表
/// 多源官方榜：酷我 bang 真榜 + B 站音乐区排行榜（榜单定义见 hot_songs_provider）
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
              const PageHeader(title: "音乐广场", subtitle: "多源榜单 · 发现好歌"),
              const SizedBox(height: 16),
              _SearchEntry(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
              ),
              const SizedBox(height: 10),
              if (DesktopContent.of(context))
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 3 : 2;
                  final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Padding(padding: const EdgeInsets.only(bottom: 18), child: Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final (index, definition) in plazaChartDefs.indexed)
                      SizedBox(width: width, child: Material(color: _tab.index == index ? t.primary.withValues(alpha: .12) : t.surface, borderRadius: BorderRadius.circular(t.radiusLg), child: InkWell(borderRadius: BorderRadius.circular(t.radiusLg), onTap: () => setState(() => _tab.animateTo(index)), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(definition.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _tab.index == index ? t.primary : t.fg, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12), Text("发现值得循环的好歌", style: TextStyle(color: t.fgMute, fontSize: 11)),
                      ]))))),
                  ]));
                }),
              // 榜单 Tab（family provider 各榜独立缓存，切换零等待）。
              // 无指示条；榜单随源扩展，超宽自动出横向滚动
              if (!DesktopContent.of(context)) Theme(
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
    final chartAsync = ref.watch(plazaChartProvider(widget.chartKey));
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );
    final playingNow = ref.watch(playbackProvider.select((s) => s.playing));
    final vipLimitedIds = ref.watch(vipLimitedTrackIdsProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, DesktopContent.of(context) ? 24 : 150),
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
                  ref.invalidate(plazaChartProvider(widget.chartKey)),
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
                        paused: !playingNow,
                        vipLimited: hit.item != null &&
                            vipLimitedIds.contains(hit.item!.id),
                        onTap: () => _playHit(hit),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 单曲点播：按榜单所属源解析 → 入库 → 开播（单曲会话，与旧热歌行一致）
  Future<void> _playHit(ChartHit hit) async {
    final needsMatch = hit.item == null;
    if (needsMatch) AppLoading.show(msg: "匹配歌曲…");
    try {
      final track = await resolveChartHit(
        hit,
        originForChartKey(widget.chartKey),
      );
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

/// 榜单歌曲行：排名 + 封面 + 歌名/歌手 + 播放态（原热歌榜列表行样式）；
/// [vipLimited] 为真时整行灰显并打 VIP 角标（会话内探测到的试听片段）
class _ChartSongRow extends StatelessWidget {
  final int rank;
  final ChartHit hit;
  final bool playing;
  final bool paused;
  final bool vipLimited;
  final VoidCallback onTap;

  const _ChartSongRow({
    required this.rank,
    required this.hit,
    required this.playing,
    required this.paused,
    required this.vipLimited,
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
                      color: playing
                          ? t.primary
                          : vipLimited
                              ? t.fgMute
                              : t.fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hit.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.fgMute),
                  ),
                ],
              ),
            ),
            // VIP 角标：会话内探测到的试听片段曲目
            if (vipLimited)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: t.fgMute, width: 0.8),
                ),
                child: Text(
                  "VIP",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: t.fgMute,
                  ),
                ),
              ),
            if (playing) EqBars(paused: paused),
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
