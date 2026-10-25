import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_toast.dart";
import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";
import "../../data/mock/mock_data.dart";
import "../../data/models/playlist.dart";

/// 广场页（对齐原型 renderPlaza）：搜索入口 + 热门歌手 + 收藏合集
class PlazaPage extends ConsumerWidget {
  const PlazaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
      children: [
        const PageHeader(title: "音乐广场", subtitle: "来自 B 站 / 酷我的海量音源"),
        const SizedBox(height: 16),
        _SearchBar(onTap: () => AppToast.show(context, "搜索页在批次 2 提供")),
        SectionHeader(title: "热门歌手", trailing: "更多"),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: mockSingers.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _SingerAvatar(singer: mockSingers[i]),
          ),
        ),
        SectionHeader(
          title: "收藏合集",
          trailing: "${mockCollections.length} 个",
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          // 格子高 = 宽/0.72：方形封面 + 标题/副题文字区（含字体行高波动留余量），
          // 390dp 窄屏实测余量 ≥15px（0.75 曾在真机字高下溢出 22px）
          childAspectRatio: 0.72,
          children: [
            for (final col in mockCollections)
              _CollectionCard(
                collection: col,
                onTap: () => AppToast.show(context, "合集详情在批次 2 提供"),
              ),
          ],
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

/// 歌手头像（原型 .singer：圆头像 + 名称）
class _SingerAvatar extends StatelessWidget {
  final MockSinger singer;

  const _SingerAvatar({required this.singer});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: const Alignment(-0.64, -0.77),
              end: const Alignment(0.64, 0.77),
              colors: coverGradientColors(singer.hue),
            ),
            border: Border.all(color: t.hairline, width: 2),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 74,
          child: Text(
            singer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.fgDim),
          ),
        ),
      ],
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
