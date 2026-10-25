import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/mock/mock_data.dart";
import "../../data/models/playlist.dart";
import "../player/player_card_page.dart";
import "playlist_detail_page.dart";

/// 歌单页（对齐原型 renderOrder）
class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
      children: [
        PageHeader(
          title: "我的歌单",
          subtitle:
              "本地 37 首 · 网络收藏 ${mockCustomPlaylists.fold<int>(0, (a, p) => a + p.count)} 首",
          trailing: GlassIconButton(
            icon: const Icon(Icons.add),
            onTap: () => AppToast.show(context, "扫描本地音乐（S3 接真数据）"),
          ),
        ),
        const SizedBox(height: 16),
        // 快捷入口两卡（原型 .qa：本地音乐 / 我喜欢）
        Row(
          children: [
            Expanded(
              child: _QuickCard(
                emoji: "🎧",
                label: "本地音乐",
                count: "37 首 · 已扫描",
                playlist: const Playlist(
                  id: "builtin:local",
                  name: "本地音乐",
                  type: PlaylistType.builtIn,
                  count: 37,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickCard(
                emoji: "💗",
                label: "我喜欢的音乐",
                count: "64 首",
                playlist: const Playlist(
                  id: "builtin:liked",
                  name: "我喜欢的音乐",
                  type: PlaylistType.builtIn,
                  count: 64,
                ),
              ),
            ),
          ],
        ),
        SectionHeader(title: "自定义歌单", trailing: "${mockCustomPlaylists.length} 个"),
        for (final pl in mockCustomPlaylists)
          _PlaylistRow(
            name: pl.name,
            count: pl.count,
            hue: pl.coverHue,
            onTap: () => _openPlaylist(context, pl),
            onMorePressed: () => _showRowActions(context, pl.name),
          ),
        SectionHeader(title: "最近播放", trailing: "全部"),
        for (final track in mockTracks.take(3))
          SongListTile(
            track: track,
            onTap: () => PlayerCardPage.start(context, ref, track),
            onMorePressed: () => _showTrackActions(context, track.name),
          ),
        // 底部留白缓冲，避免贴住 Dock
        SizedBox(height: t.radiusLg),
      ],
    );
  }

  // 打开歌单详情（mock 阶段直接传 Playlist 对象；S3 改按 id 取数）
  void _openPlaylist(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: playlist)),
    );
  }

  // 列表行长按/更多：底部操作面板（批次 2 起接真实动作）
  void _showRowActions(BuildContext context, String name) {
    AppSheet.show(
      context,
      title: name,
      actions: [
        AppSheetAction(
          icon: Icons.edit_outlined,
          label: "重命名",
          onTap: () => AppToast.show(context, "S3 接真数据后可用"),
        ),
        AppSheetAction(
          icon: Icons.delete_outline,
          label: "删除歌单",
          danger: true,
          onTap: () => AppToast.show(context, "S3 接真数据后可用"),
        ),
      ],
    );
  }

  void _showTrackActions(BuildContext context, String name) {
    AppSheet.show(
      context,
      title: name,
      actions: [
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: "下一首播放",
          onTap: () => AppToast.show(context, "播放队列在批次 3/4 提供"),
        ),
        AppSheetAction(
          icon: Icons.playlist_add,
          label: "加入歌单",
          onTap: () => AppToast.show(context, "S3 接真数据后可用"),
        ),
      ],
    );
  }
}

/// 快捷入口卡（原型 .qa .qi：大 emoji 沉底 + 标签/计数）
class _QuickCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String count;
  final Playlist playlist;

  const _QuickCard({
    required this.emoji,
    required this.label,
    required this.count,
    required this.playlist,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailPage(playlist: playlist),
        ),
      ),
      pressedScale: 0.97,
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radiusLg),
          color: t.surface,
          border: Border.all(color: t.hairline, width: 1),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.fg),
                ),
                Text(count, style: TextStyle(fontSize: 12, color: t.fgDim)),
              ],
            ),
            // 大 emoji 沉底溢出（原型 .em 64px opacity .16）
            Positioned(
              right: -10,
              bottom: -14,
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: 56,
                  color: t.fgDim.withValues(alpha: 0.16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌单行（原型 .plid：字首封面 + 名称/计数 + 更多）
class _PlaylistRow extends StatelessWidget {
  final String name;
  final int count;
  final int? hue;
  final VoidCallback onTap;
  final VoidCallback onMorePressed;

  const _PlaylistRow({
    required this.name,
    required this.count,
    required this.hue,
    required this.onTap,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radiusMd),
      splashColor: t.surface2,
      highlightColor: t.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            CoverPlaceholder(
              hue: hue,
              text: name,
              size: 54,
              radius: t.radiusMd,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.fg),
                  ),
                  const SizedBox(height: 3),
                  Text("$count 首", style: TextStyle(fontSize: 12.5, color: t.fgDim)),
                ],
              ),
            ),
            IconButton(
              onPressed: onMorePressed,
              icon: const Icon(Icons.more_vert),
              iconSize: 18,
              color: t.fgMute,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
