import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/skeleton.dart";
import "../../data/models/playlist.dart";
import "../../data/singers_provider.dart";
import "../playlist/playlists_provider.dart" show collectionsProvider;
import "collection_detail_page.dart";
import "search_page.dart";
import "singer_list_page.dart";

/// 广场页（对齐原型 renderPlaza）：搜索入口 + 热门歌手 + 收藏合集
class PlazaPage extends ConsumerWidget {
  const PlazaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final singersAsync = ref.watch(hotSingersProvider);
    final collectionsAsync = ref.watch(collectionsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
      children: [
        const PageHeader(title: "音乐广场", subtitle: "来自 B 站 / 酷我的海量音源"),
        const SizedBox(height: 16),
        _SearchBar(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
        ),
        // 热门歌手：内置歌手数据（chinese.json），加载中骨架、空/失败整区隐藏
        if (singersAsync.value case final singers? when singers.isNotEmpty) ...[
          SectionHeader(
            title: "热门歌手",
            trailing: "更多",
            // 对齐 2.7.0：更多 → 歌手列表页（数据同源已 keepAlive，直接传入零等待）
            onTrailingTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SingerListPage(singers: singers)),
            ),
          ),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: singers.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _SingerAvatar(singer: singers[i]),
            ),
          ),
        ],
        // 收藏合集：真数据（收藏动作落库后 invalidate）
        SectionHeader(
          title: "收藏合集",
          trailing: collectionsAsync.value == null
              ? null
              : "${collectionsAsync.value!.length} 个",
        ),
        collectionsAsync.when(
          loading: () => const SkeletonListView(rows: 2),
          error: (e, _) => EmptyState(
            compact: true,
            emoji: "⚠️",
            title: "合集加载失败",
            subtitle: "点击重试",
            action: GlassChip(
              label: "重试",
              onTap: () => ref.invalidate(collectionsProvider),
            ),
          ),
          data: (collections) => collections.isEmpty
              ? EmptyState(
                  compact: true,
                  emoji: "📻",
                  title: "还没有收藏合集",
                  subtitle: "在搜索中收藏喜欢的合集",
                  action: GlassChip(
                    label: "去搜索",
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    ),
                  ),
                )
              : GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  // 格子高 = 宽/0.72：方形封面 + 标题/副题文字区（含字体行高波动留余量），
                  // 390dp 窄屏实测余量 ≥15px（0.75 曾在真机字高下溢出 22px）
                  childAspectRatio: 0.72,
                  children: [
                    for (final col in collections)
                      _CollectionCard(
                        collection: col,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CollectionDetailPage(collection: col),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 搜索入口条（原型 .searchbar）
class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: t.surface,
          border: Border.all(color: t.hairline, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: t.fgDim),
            const SizedBox(width: 10),
            Text(
              "搜索歌曲 / 歌手 / 合集",
              style: TextStyle(fontSize: 14, color: t.fgDim),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌手头像（原型 .singer：圆头像真实封面 + 名称；点击进入歌手歌单）
class _SingerAvatar extends StatelessWidget {
  final SingerEntry singer;

  const _SingerAvatar({required this.singer});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      pressedScale: 0.94,
      onTap: () => openSingerDetail(context, singer),
      child: Column(
        children: [
          // 头像用歌手条目级写真（对齐 2.7.0），缺失回退首曲封面
          // 直径 56（所有者 2026-10-27 指定：原 74 缩减约 1/4）
          CoverPlaceholder(
            cover: singer.cover ?? singer.tracks.firstOrNull?.cover,
            text: singer.name,
            size: 56,
            radius: 28,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 56,
            child: Text(
              singer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.fgDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// 合集卡片（原型 .cover：方形封面 + 角标 + 标题/副题）
class _CollectionCard extends StatelessWidget {
  final Playlist collection;
  final VoidCallback onTap;

  const _CollectionCard({required this.collection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      pressedScale: 0.97,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.radiusLg),
                    gradient: LinearGradient(
                      begin: const Alignment(-0.64, -0.77),
                      end: const Alignment(0.64, 0.77),
                      colors: coverGradientColors(collection.coverHue ?? 212),
                    ),
                  ),
                ),
                // 角标（原型 .badge：黑透玻璃胶囊）
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: t.coverBadgeBg,
                    ),
                    child: Text(
                      "合集",
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: t.coverBadgeFg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            collection.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.fg),
          ),
          const SizedBox(height: 3),
          Text(
            "收藏 · ${collection.count} 首",
            style: TextStyle(fontSize: 12, color: t.fgDim),
          ),
        ],
      ),
    );
  }
}
