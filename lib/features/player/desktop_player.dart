import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/navigation/desktop_navigation.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/empty_state.dart";
import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "../download/download_actions.dart";
import "../playlist/add_to_playlist_sheet.dart";
import "../playlist/playlists_provider.dart";
import "../playlist/track_edit_dialog.dart";
import "comment_page.dart";
import "play_mode.dart";
import "playback_provider.dart";
import "playback_speed.dart";
import "playback_speed_sheet.dart";
import "player_card_page.dart";
import "queue_sheet.dart";
import "sleep_timer_sheet.dart";

final _trackLikedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, id) async {
  // 所有收藏入口都会刷新数量；借此重新读取库态，避免播放器快照上的 liked 过时。
  ref.watch(likedCountProvider);
  return (await TrackRepository().getById(id))?.liked ?? false;
});

Future<void> _toggleLike(
    BuildContext context, WidgetRef ref, Track track) async {
  try {
    final liked = await ref.read(_trackLikedProvider(track.id).future);
    await TrackRepository().setLiked(track.id, !liked);
    if (!context.mounted) return;
    ref.invalidate(likedCountProvider);
    ref.invalidate(playlistDetailTracksProvider("builtin:liked"));
    AppToast.show(context, liked ? "已取消喜欢" : "已加入我喜欢的音乐");
  } catch (error) {
    print("更新收藏失败：$error");
    if (context.mounted) AppToast.show(context, "收藏更新失败，请重试");
  }
}

void _openPlayer(WidgetRef ref) => ref
    .read(desktopNavigationProvider.notifier)
    .open(const DesktopDestination("player", "正在播放"));

List<AppSheetAction> _trackActions(
        BuildContext context, WidgetRef ref, Track track) =>
    [
      if (track.origin != OriginType.local)
        AppSheetAction(
            icon: Icons.download_outlined,
            label: "下载",
            onTap: () => downloadTrack(context, track)),
      AppSheetAction(
          icon: Icons.edit_outlined,
          label: "编辑信息",
          onTap: () => showTrackEditDialog(context, ref, track)),
      AppSheetAction(
          icon: Icons.library_add_outlined,
          label: "加入歌单",
          onTap: () => showAddToPlaylistSheet(context, ref, [track])),
      if (track.origin == OriginType.netease || track.origin == OriginType.kuwo)
        AppSheetAction(
            icon: Icons.comment_outlined,
            label: "查看评论",
            onTap: () => CommentPage.open(context, track)),
      AppSheetAction(
          icon: Icons.timer_outlined,
          label: "定时关闭",
          onTap: () => showSleepTimerSheet(context, ref)),
    ];

class _LikeButton extends ConsumerWidget {
  const _LikeButton(this.track);
  final Track track;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final liked = ref.watch(_trackLikedProvider(track.id)).value ?? track.liked;
    return IconButton(
        tooltip: liked ? "取消喜欢" : "喜欢",
        onPressed: () => _toggleLike(context, ref, track),
        iconSize: 19,
        icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
            color: liked ? t.primary : t.fgDim));
  }
}

class DesktopPlayerBar extends ConsumerWidget {
  const DesktopPlayerBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final data = ref.watch(playbackProvider.select((s) => (
          track: s.track,
          playing: s.playing,
          buffering: s.buffering,
          duration: s.duration,
          mode: s.mode,
          speed: s.speed
        )));
    final commands = ref.read(playbackProvider.notifier);
    final track = data.track;
    final expanded = ref.watch(
        desktopNavigationProvider.select((state) => state.route == "player"));
    return DesktopContent(
        child: Builder(
            builder: (context) => Container(
                  key: const Key("desktop_player_bar"),
                  height: 104,
                  decoration: BoxDecoration(
                      color: t.bg2.withValues(alpha: .94),
                      border: Border(top: BorderSide(color: t.hairline))),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1050;
                    return Row(children: [
                      SizedBox(
                          width: wide ? 230 : 190,
                          child: Row(children: [
                            InkWell(
                                onTap: track == null
                                    ? null
                                    : () => _openPlayer(ref),
                                child: CoverPlaceholder(
                                    cover: track?.effectiveCover,
                                    text: track?.effectiveName,
                                    size: 46,
                                    radius: t.radiusSm)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: InkWell(
                                    onTap: track == null
                                        ? null
                                        : () => _openPlayer(ref),
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(track?.effectiveName ?? "选择一首音乐",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: t.fg,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(
                                              track?.effectiveAuthor ??
                                                  "从音乐库开始聆听",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: t.fgMute,
                                                  fontSize: 10)),
                                        ]))),
                            if (track != null) _LikeButton(track),
                          ])),
                      const SizedBox(width: 20),
                      Expanded(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                      tooltip: _modeLabel(data.mode),
                                      iconSize: 18,
                                      onPressed: commands.cycleMode,
                                      icon: Icon(_modeIcon(data.mode),
                                          color: t.fgDim)),
                                  IconButton(
                                      key: const Key("desktop_previous"),
                                      tooltip: "上一首",
                                      iconSize: 21,
                                      onPressed: track == null
                                          ? null
                                          : commands.previous,
                                      icon: const Icon(Icons.skip_previous)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: FilledButton(
                                          key: const Key("desktop_toggle_play"),
                                          style: FilledButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              shape: const CircleBorder()),
                                          onPressed: track == null
                                              ? null
                                              : commands.toggle,
                                          child: data.buffering
                                              ? SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: t.primaryInk))
                                              : Icon(
                                                  data.playing
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                  size: 22))),
                                  const SizedBox(width: 8),
                                  IconButton(
                                      key: const Key("desktop_next"),
                                      tooltip: "下一首",
                                      iconSize: 21,
                                      onPressed:
                                          track == null ? null : commands.next,
                                      icon: const Icon(Icons.skip_next)),
                                  IconButton(
                                      tooltip: "待播放",
                                      iconSize: 18,
                                      onPressed: () =>
                                          showPlaybackQueueSheet(context),
                                      icon: const Icon(
                                          Icons.queue_music_outlined)),
                                ]),
                            PlayerSeekBar(
                                key: ValueKey(track?.id),
                                durationSec: data.duration.inSeconds > 0
                                    ? data.duration.inSeconds
                                    : track?.duration ?? 0,
                                compact: true),
                          ])),
                      const SizedBox(width: 20),
                      SizedBox(
                          width: wide ? 250 : 154,
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                    style: TextButton.styleFrom(
                                        minimumSize: const Size(42, 32),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5)),
                                    onPressed: () =>
                                        showPlaybackSpeedSheet(context),
                                    child: Text(playbackSpeedLabel(data.speed),
                                        style: const TextStyle(fontSize: 11))),
                                if (wide)
                                  const Expanded(child: _DesktopVolume()),
                                IconButton(
                                    tooltip: "待播放",
                                    iconSize: 19,
                                    onPressed: () =>
                                        showPlaybackQueueSheet(context),
                                    icon:
                                        const Icon(Icons.queue_music_outlined)),
                                IconButton(
                                    key: const Key("desktop_player_expand"),
                                    tooltip: expanded ? "收起播放页" : "展开播放页",
                                    iconSize: 19,
                                    onPressed: () {
                                      if (expanded) {
                                        ref
                                            .read(desktopNavigationProvider
                                                .notifier)
                                            .back();
                                      } else {
                                        _openPlayer(ref);
                                      }
                                    },
                                    icon: Icon(expanded
                                        ? Icons.close_fullscreen
                                        : Icons.open_in_full)),
                              ])),
                    ]);
                  }),
                )));
  }
}

class _DesktopVolume extends ConsumerStatefulWidget {
  const _DesktopVolume();
  @override
  ConsumerState<_DesktopVolume> createState() => _DesktopVolumeState();
}

class _DesktopVolumeState extends ConsumerState<_DesktopVolume> {
  double? _preview;
  int _request = 0;
  Future<void> _commit(double value) async {
    final request = ++_request;
    await ref.read(playbackProvider.notifier).setVolume(value);
    if (mounted && request == _request) {
      setState(() => _preview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(playbackProvider.select((s) => s.volume));
    final commands = ref.read(playbackProvider.notifier);
    return Row(children: [
      IconButton(
          tooltip: volume == 0 ? "取消静音" : "静音",
          iconSize: 18,
          onPressed: () {
            setState(() => _preview = null);
            commands.toggleMute();
          },
          icon: Icon(volume == 0
              ? Icons.volume_off_outlined
              : Icons.volume_up_outlined)),
      Expanded(
          child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10)),
              child: Slider(
                  key: const Key("desktop_volume"),
                  value: _preview ?? volume,
                  onChanged: (value) => setState(() => _preview = value),
                  onChangeEnd: _commit))),
    ]);
  }
}

String _modeLabel(PlayMode mode) => switch (mode) {
      PlayMode.singleLoop => "单曲循环",
      PlayMode.listLoop => "列表循环",
      PlayMode.shuffle => "随机播放",
      PlayMode.sequential => "顺序播放"
    };
IconData _modeIcon(PlayMode mode) => switch (mode) {
      PlayMode.singleLoop => Icons.repeat_one,
      PlayMode.listLoop => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.sequential => Icons.format_list_numbered
    };

class DesktopNowPlayingPanel extends ConsumerWidget {
  const DesktopNowPlayingPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final track = ref.watch(playbackProvider.select((state) => state.track));
    final liked = track == null
        ? false
        : ref.watch(_trackLikedProvider(track.id)).value ?? track.liked;
    return DesktopContent(
        child: Builder(
            builder: (context) => Container(
                  decoration: BoxDecoration(
                      color: t.surface,
                      border: Border(left: BorderSide(color: t.hairline))),
                  child: track == null
                      ? const Center(
                          child: EmptyState(
                              compact: true,
                              asset: "assets/illustrations/empty_music.svg",
                              title: "此刻，听点什么",
                              subtitle: "播放一首喜欢的音乐"))
                      : PlayerCardContent(
                          sidePanel: true,
                          track: track,
                          liked: liked,
                          onToggleLike: () => _toggleLike(context, ref, track),
                          onHeaderAction: () => _openPlayer(ref),
                        ),
                )));
  }
}

class DesktopPlayerPage extends ConsumerWidget {
  const DesktopPlayerPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final track = ref.watch(playbackProvider.select((state) => state.track));
    if (track == null) {
      return const EmptyState(
          asset: "assets/illustrations/empty_music.svg",
          title: "还没有正在播放的音乐",
          subtitle: "先从歌单或广场选择一首歌");
    }
    // 左栏按可用高度缩放封面，不滚动；右栏歌词始终占满内容区高度。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: LayoutBuilder(
          builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    key: const Key("desktop_player_artwork_panel"),
                    width: (constraints.maxWidth * .38).clamp(180, 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(children: [
                        const PlayerLyricTools(horizontalPadding: 0),
                        const SizedBox(height: 16),
                        Flexible(
                            child: AspectRatio(
                          aspectRatio: 1,
                          child: LayoutBuilder(
                              builder: (context, box) => CoverPlaceholder(
                                  key: const Key("desktop_player_cover"),
                                  cover: track.effectiveCover,
                                  text: track.effectiveName,
                                  size: box.maxWidth,
                                  radius: t.radiusXl)),
                        )),
                        const SizedBox(height: 16),
                        _DesktopTrackActions(track),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 32),
                  const Expanded(
                      child:
                          PlayerLyricsView(expanded: true, showTools: false)),
                ],
              )),
    );
  }
}

class _DesktopTrackActions extends ConsumerWidget {
  const _DesktopTrackActions(this.track);
  final Track track;
  static const _buttonExtent = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final liked = ref.watch(_trackLikedProvider(track.id)).value ?? track.liked;
    final actions = [
      AppSheetAction(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          label: liked ? "取消喜欢" : "喜欢",
          onTap: () => _toggleLike(context, ref, track)),
      ..._trackActions(context, ref, track),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      // 仅将放不下的操作移入更多；预留更多按钮自身的位置，避免窄窗溢出。
      final slots = (constraints.maxWidth / _buttonExtent)
          .floor()
          .clamp(1, actions.length);
      final visibleCount = slots >= actions.length ? actions.length : slots - 1;
      final overflow = actions.skip(visibleCount).toList();
      return Row(
          key: const Key("desktop_track_actions"),
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final action in actions.take(visibleCount))
              SizedBox.square(
                  dimension: _buttonExtent,
                  child: IconButton(
                      tooltip: action.label,
                      onPressed: action.onTap,
                      icon: Icon(action.icon,
                          color: action.icon == Icons.favorite
                              ? t.primary
                              : t.fgDim))),
            if (overflow.isNotEmpty)
              SizedBox.square(
                  dimension: _buttonExtent,
                  child: IconButton(
                      tooltip: "更多操作",
                      onPressed: () => AppSheet.show(context,
                          title: "更多操作", actions: overflow),
                      icon: Icon(Icons.more_horiz, color: t.fgDim))),
          ]);
    });
  }
}
