import "package:flutter/material.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";
import "../../data/models/playlist.dart";
import "../../data/singers_provider.dart";
import "../player/mini_player_bar.dart";
import "../playlist/playlist_detail_page.dart";

/// 打开歌手歌单详情（广场头像/歌手列表共用，跳转行为保持一致）
/// 曲目行统一用外面同款歌手封面（写真缺失回退首曲封面，与广场头像口径一致）
void openSingerDetail(BuildContext context, SingerEntry singer) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlaylistDetailPage(
        playlist: Playlist(
          id: "singer:${singer.id}",
          name: singer.name,
          type: PlaylistType.custom,
        ),
        tracks: singer.tracks,
        trackCover: singer.cover ?? singer.tracks.firstOrNull?.cover,
      ),
    ),
  );
}

/// 歌手列表页（广场「热门歌手 · 更多」入口，行为对齐 2.7.0 SingerList）
/// 数据由入口页传入（hotSingersProvider 已 keepAlive，广场先加载则零等待）
class SingerListPage extends StatelessWidget {
  final List<SingerEntry> singers;

  const SingerListPage({super.key, required this.singers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              children: [
                const Align(alignment: Alignment.centerLeft, child: BackLink()),
                const PageHeader(title: "歌手列表", subtitle: "内置热门歌手"),
                for (final singer in singers) ...[
                  const SizedBox(height: 6),
                  _SingerRow(singer: singer),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 歌手行：圆角方形写真 + 名称/副题 + 箭头（2.7.0 ListTile 同信息量，风格 A 版式）
class _SingerRow extends StatelessWidget {
  final SingerEntry singer;

  const _SingerRow({required this.singer});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: () => openSingerDetail(context, singer),
      pressedScale: 0.97,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CoverPlaceholder(
              cover: singer.cover ?? singer.tracks.firstOrNull?.cover,
              text: singer.name,
              size: 52,
              radius: 14,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                singer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.fg),
              ),
            ),
            // 副题：desc 优先，空则曲目数兜底（保持行信息量一致）
            Text(
              singer.desc.isNotEmpty ? singer.desc : "${singer.tracks.length} 首",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: t.fgDim),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: t.fgDim),
          ],
        ),
      ),
    );
  }
}
