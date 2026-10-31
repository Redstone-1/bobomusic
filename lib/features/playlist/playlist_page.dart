import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/skeleton.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/playlist.dart";
import "../../data/models/track.dart";
import "../../data/repositories/history_repository.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../download/download_actions.dart";
import "../download/downloads_page.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "add_to_playlist_sheet.dart";
import "playlist_detail_page.dart";
import "playlists_provider.dart";
import "track_edit_dialog.dart";

/// 歌单页（对齐原型 renderOrder；S3.3 接真数据：歌单 CRUD / 我喜欢 / 播放队列）
class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final playlistsAsync = ref.watch(playlistsProvider);
    final likedCount = ref.watch(likedCountProvider);
    final localCount = ref.watch(localCountProvider);
    final recentAsync = ref.watch(recentTracksProvider);
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );
    // 播放状态机在切歌前已写入 history；track 变化后刷新最近播放
    ref.listen(playbackProvider.select((s) => s.track?.id), (_, __) {
      ref.invalidate(recentTracksProvider);
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
      children: [
        PageHeader(
          title: "我的歌单",
          subtitle: "本地 ${localCount.value ?? 0} 首 · 网络收藏 0 首",
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassIconButton(
                key: const Key("downloads_entry"),
                icon: const Icon(Icons.download_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DownloadsPage()),
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: const Icon(Icons.add),
                onTap: () => _createPlaylist(context, ref),
              ),
            ],
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
                // 0 首时引导扫描，有数后展示数量
                count: switch (localCount.value) {
                  null => "…",
                  0 => "待扫描",
                  final n => "$n 首",
                },
                playlist: const Playlist(
                  id: "builtin:local",
                  name: "本地音乐",
                  type: PlaylistType.builtIn,
                  count: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickCard(
                emoji: "💗",
                label: "我喜欢的音乐",
                count: "${likedCount.value ?? 0} 首",
                playlist: const Playlist(
                  id: "builtin:liked",
                  name: "我喜欢的音乐",
                  type: PlaylistType.builtIn,
                  count: 0,
                ),
              ),
            ),
          ],
        ),
        SectionHeader(
          title: "自定义歌单",
          trailing: playlistsAsync.value == null
              ? null
              : "${playlistsAsync.value!.length} 个",
        ),
        // 歌单目录三态
        playlistsAsync.when(
          loading: () => const SkeletonListView(rows: 3),
          error: (e, _) => EmptyState(
            compact: true,
            asset: "assets/illustrations/empty_alert.svg",
            title: "歌单加载失败",
            subtitle: "点击重试",
            action: GlassChip(
              label: "重试",
              onTap: () => ref.invalidate(playlistsProvider),
            ),
          ),
          data: (playlists) => playlists.isEmpty
              ? const EmptyState(
                  compact: true,
                  asset: "assets/illustrations/empty_collection.svg",
                  title: "还没有歌单",
                  subtitle: "点右上角 + 创建第一个歌单",
                )
              : Column(
                  children: [
                    for (final pl in playlists)
                      _PlaylistRow(
                        name: pl.name,
                        count: pl.count,
                        onTap: () => _openPlaylist(context, pl),
                        onMorePressed: () =>
                            _showRowActions(context, ref, pl),
                      ),
                  ],
                ),
        ),
        SectionHeader(
          title: "最近播放",
          trailing: recentAsync.value?.isNotEmpty == true ? "清空" : null,
          onTrailingTap: () => _clearRecent(context, ref),
        ),
        recentAsync.when(
          loading: () => const SkeletonListView(rows: 3),
          error: (e, _) => EmptyState(
            compact: true,
            asset: "assets/illustrations/empty_alert.svg",
            title: "最近播放加载失败",
            subtitle: "点击重试",
            action: GlassChip(
              label: "重试",
              onTap: () => ref.invalidate(recentTracksProvider),
            ),
          ),
          data: (recent) => recent.isEmpty
              ? const EmptyState(
                  compact: true,
                  asset: "assets/illustrations/empty_music.svg",
                  title: "还没有播放记录",
                  subtitle: "播放过的歌曲会出现在这里",
                )
              : Column(
                  children: [
                    for (final track in recent.take(10))
                      SongListTile(
                        track: track,
                        playing: track.id == currentTrackId,
                        onTap: () => PlayerCardPage.start(
                          context,
                          ref,
                          track,
                          queue: recent,
                        ),
                        onMorePressed: () =>
                            _showRecentActions(context, ref, track),
                      ),
                  ],
                ),
        ),
        // 底部留白缓冲，避免贴住 Dock
        SizedBox(height: t.radiusLg),
      ],
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final existing = ref.read(playlistsProvider).value?.length ?? 0;
    if (existing >= 20) {
      AppToast.show(context, "最多创建 20 个歌单");
      return;
    }
    final name = await AppDialog.input(
      context,
      title: "新建歌单",
      hint: "歌单名（1~20 字）",
      validator: _validateName,
    );
    if (name == null || !context.mounted) return;
    try {
      await ref.read(playlistsProvider.notifier).create(name.trim());
      if (context.mounted) AppToast.show(context, "已创建「$name」");
    } catch (_) {
      if (context.mounted) AppToast.show(context, "歌单名已存在");
    }
  }

  Future<void> _clearRecent(BuildContext context, WidgetRef ref) async {
    final ok = await AppDialog.confirm(
      context,
      title: "清空最近播放",
      message: "只清空播放记录，不会删除歌曲、歌单或下载文件。",
      confirmText: "清空",
      danger: true,
    );
    if (ok != true || !context.mounted) return;
    await HistoryRepository().clear();
    ref.invalidate(recentTracksProvider);
    if (context.mounted) AppToast.show(context, "已清空最近播放");
  }

  void _showRecentActions(BuildContext context, WidgetRef ref, Track track) {
    AppSheet.show(
      context,
      title: track.effectiveName,
      actions: [
        AppSheetAction(
          icon: Icons.edit_outlined,
          label: "编辑信息",
          onTap: () => showTrackEditDialog(context, ref, track),
        ),
        AppSheetAction(
          icon: Icons.library_add_outlined,
          label: "加入歌单",
          onTap: () => showAddToPlaylistSheet(context, ref, [track]),
        ),
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: "下一首播放",
          onTap: () async {
            await TrackRepository().upsert(track);
            await QueueRepository().insertNext(track.id, atPosition: 0);
            ref.invalidate(queueEntriesProvider);
            if (context.mounted) AppToast.show(context, "已设为下一首播放");
          },
        ),
        AppSheetAction(
          icon: Icons.download_outlined,
          label: "下载",
          onTap: () => downloadTrack(context, track),
        ),
      ],
    );
  }

  /// 歌单名校验（§2.1 沿用旧版：非空、≤20 字、不能数字开头）
  String? _validateName(String? value) {
    final name = value?.trim() ?? "";
    if (name.isEmpty) return "歌单名不能为空";
    if (name.length > 20) return "歌单名最长 20 个字符";
    if (RegExp(r"^\d").hasMatch(name)) return "歌单名不能以数字开头";
    return null;
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: playlist)),
    );
  }

  void _showRowActions(BuildContext context, WidgetRef ref, Playlist pl) {
    AppSheet.show(
      context,
      title: pl.name,
      actions: [
        AppSheetAction(
          icon: Icons.edit_outlined,
          label: "重命名",
          onTap: () => _renamePlaylist(context, ref, pl),
        ),
        AppSheetAction(
          icon: Icons.delete_outline,
          label: "删除歌单",
          danger: true,
          onTap: () => _deletePlaylist(context, ref, pl),
        ),
      ],
    );
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist pl,
  ) async {
    final name = await AppDialog.input(
      context,
      title: "重命名歌单",
      initial: pl.name,
      validator: _validateName,
    );
    if (name == null || !context.mounted) return;
    try {
      await ref.read(playlistsProvider.notifier).rename(pl.id, name.trim());
      if (context.mounted) AppToast.show(context, "已重命名");
    } catch (_) {
      if (context.mounted) AppToast.show(context, "歌单名已存在");
    }
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist pl,
  ) async {
    final ok = await AppDialog.confirm(
      context,
      title: "删除歌单",
      message: "歌单「${pl.name}」将被删除，歌曲不受影响。",
      danger: true,
      confirmText: "删除",
    );
    if (!ok || !context.mounted) return;
    await ref.read(playlistsProvider.notifier).remove(pl.id);
    if (context.mounted) AppToast.show(context, "已删除");
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
  final VoidCallback onTap;
  final VoidCallback onMorePressed;

  const _PlaylistRow({
    required this.name,
    required this.count,
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
