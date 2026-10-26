import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_loading.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/aurora_progress_bar.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/origin_tag.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/track.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/lyric/lrc.dart";
import "../../origin_sdk/lyric/lyric_types.dart";
import "../download/download_actions.dart";
import "../playlist/playlists_provider.dart" show likedCountProvider, queueTracksProvider;
import "lyric_provider.dart";
import "open_bilibili.dart";
import "play_mode.dart";
import "playback_provider.dart";
import "sleep_timer_sheet.dart";

/// 全屏播放卡片（对齐原型 .player：歌词 + seek + 控制区 + 动作行）
/// 所有者 2026-10-26 反馈：移除黑胶，播放卡默认只显示歌词
class PlayerCardPage extends ConsumerStatefulWidget {
  const PlayerCardPage({super.key});

  /// 仅开播（列表行点击用）：不弹卡，播放状态由迷你条承接
  /// 播放即入库：喜欢/队列/历史的落点（upsert 保留已有喜欢/下载态）
  /// [queue] 播放上下文（§3.4-4：点播时所在列表），缺省为单曲
  static void start(
    BuildContext context,
    WidgetRef ref,
    Track track, {
    List<Track>? queue,
  }) {
    TrackRepository().upsert(track);
    ref.read(playbackProvider.notifier).play(track, queue: queue);
  }

  /// 开播并以上滑转场打开播放卡（迷你条点击用；原型 .overlay 上滑 .5s）
  /// 已是当前曲目时只开卡不重播——保留会话队列与播放进度
  static void open(BuildContext context, WidgetRef ref, Track track) {
    if (ref.read(playbackProvider).track?.id != track.id) {
      start(context, ref, track);
    }
    final t = AuroraTokens.of(context);
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: t.motionSlow,
        reverseTransitionDuration: t.motionNormal,
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PlayerCardPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: t.motionCurveEmphasized)),
          child: child,
        ),
      ),
    );
  }

  @override
  ConsumerState<PlayerCardPage> createState() => _PlayerCardPageState();
}

class _PlayerCardPageState extends ConsumerState<PlayerCardPage> {
  bool? _likedOverride; // 相对 track.liked 的本地覆盖（写库后与库态一致）

  @override
  void initState() {
    super.initState();
    // 打开播放卡即预加载歌词（库内有则直接显示；无则自动匹配三顺位）
    final track = ref.read(playbackProvider).track;
    if (track != null) {
      Future.microtask(() {
        if (mounted) {
          ref.read(lyricControllerProvider.notifier).loadFor(track);
        }
      });
    }
  }

  /// 喜欢/取消喜欢：心形与动作行共用同一份库态/本地覆盖
  void _toggleLike(Track track) {
    final newLiked = !(_likedOverride ?? track.liked);
    TrackRepository().setLiked(track.id, newLiked);
    ref.invalidate(likedCountProvider);
    setState(() => _likedOverride = newLiked);
  }

  @override
  Widget build(BuildContext context) {
    // 切歌时重新加载歌词（保持同一播放卡内的歌词跟随），
    // 并清掉上一曲的喜欢覆盖，回退新曲库态（防跨曲残留）
    ref.listen(playbackProvider.select((s) => s.track), (_, next) {
      if (next != null) {
        setState(() => _likedOverride = null);
        ref.read(lyricControllerProvider.notifier).loadFor(next);
      }
    });
    // 高频 position 不进本层：只订阅曲目/播放态/总时长，进度由 _SeekRow/_LyricView 各自 select
    final track = ref.watch(playbackProvider.select((s) => s.track));
    final duration = ref.watch(playbackProvider.select((s) => s.duration));
    // 理论不可达（打开前必 play）；防御：无曲直接回退
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    // 引擎真时长优先，未就绪回退曲目元数据（避免除零）
    final durationSec = duration.inSeconds > 0
        ? duration.inSeconds
        : track.duration ?? 240;

    return Scaffold(
      // 背景与主壳一致（极光光球，所有者 2026-10-27 指定：不再单独设封面色背景）
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(onClose: () => Navigator.of(context).pop()),
              // 播放卡只保留歌词视图（所有者 2026-10-26 反馈：不要黑胶）
              const Expanded(
                child: _LyricView(key: Key("player_lyrics")),
              ),
              _MetaRow(track: track),
              const SizedBox(height: 12),
              // 参考酷狗：动作行在进度条上方，主控制行在进度条下方
              _ActionsRow(
                liked: _likedOverride ?? track.liked,
                onToggleLike: () => _toggleLike(track),
              ),
              const SizedBox(height: 10),
              _SeekRow(durationSec: durationSec),
              _ControlsRow(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶栏：收起 / 正在播放 / 更多（更多 = 定时关闭；歌词工具在歌词视图内）
class _TopBar extends ConsumerWidget {
  final VoidCallback onClose;

  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final sleep = ref.watch(playbackProvider.select(sleepTimerLabel));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      child: Row(
        children: [
          GlassIconButton(
            key: const Key("player_close"),
            icon: const Icon(Icons.keyboard_arrow_down),
            onTap: onClose,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  "正在播放",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.fg),
                ),
                const SizedBox(height: 3),
                Text(
                  sleep == "未开启" ? "啵啵音乐" : "啵啵音乐 · $sleep",
                  style: TextStyle(fontSize: 12, color: t.fgDim),
                ),
              ],
            ),
          ),
          GlassIconButton(
            key: const Key("player_more"),
            icon: const Icon(Icons.more_horiz),
            onTap: () => _openMore(context, ref),
          ),
        ],
      ),
    );
  }

  void _openMore(BuildContext context, WidgetRef ref) {
    final state = ref.read(playbackProvider);
    final track = state.track;
    AppSheet.show(
      context,
      title: "更多",
      actions: [
        AppSheetAction(
          icon: Icons.timer_outlined,
          label: "定时关闭（${sleepTimerLabel(state)}）",
          onTap: () => showSleepTimerSheet(context, ref),
        ),
        if (track != null && track.origin == OriginType.bili)
          AppSheetAction(
            icon: Icons.open_in_new,
            label: "去 B 站看视频",
            onTap: () async {
              final opened = await openBilibiliVideo(track);
              if (!opened && context.mounted) {
                AppToast.show(context, "无法打开 B 站");
              }
            },
          ),
      ],
    );
  }
}

/// 曲目信息（D11：播放页显示音源标签）
class _MetaRow extends StatelessWidget {
  final Track track;

  const _MetaRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: t.fg),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    OriginTag(origin: track.origin),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        track.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: t.fgDim),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间 + seek 条（高频进度只重建本行；seek 按真时长换算秒）
class _SeekRow extends ConsumerWidget {
  final int durationSec;

  const _SeekRow({required this.durationSec});

  static String _fmt(int sec) =>
      "${sec ~/ 60}:${(sec % 60).toString().padLeft(2, "0")}";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final (positionMs, durationMs) = ref.watch(
      playbackProvider.select(
        (s) => (s.position.inMilliseconds, s.duration.inMilliseconds),
      ),
    );
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          Text(
            _fmt((durationSec * progress).round()),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.fgDim),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AuroraProgressBar(
              value: progress,
              height: 4,
              onChanged: (fraction) => ref
                  .read(playbackProvider.notifier)
                  .seek(Duration(seconds: (durationSec * fraction).round())),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmt(durationSec),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.fgDim),
          ),
        ],
      ),
    );
  }
}

/// 主控制区（模式 / 上一首 / 播放 / 下一首 / 队列）
class _ControlsRow extends ConsumerWidget {
  static const _modeIcons = {
    PlayMode.singleLoop: Icons.repeat_one,
    PlayMode.listLoop: Icons.repeat,
    PlayMode.shuffle: Icons.shuffle,
    PlayMode.sequential: Icons.format_list_numbered,
  };

  const _ControlsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final playing = ref.watch(playbackProvider.select((s) => s.playing));
    final mode = ref.watch(playbackProvider.select((s) => s.mode));
    final notifier = ref.read(playbackProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: "播放模式：${mode.label}",
            onPressed: () {
              notifier.cycleMode();
              AppToast.show(context, mode.next.label);
            },
            icon: Icon(_modeIcons[mode]),
            // 播放模式是常驻控制项，统一使用主题色（不再只有单曲循环高亮）
            color: t.primary,
            iconSize: 24,
          ),
          IconButton(
            onPressed: notifier.previous,
            icon: const Icon(Icons.skip_previous),
            color: t.primary,
            iconSize: 30,
          ),
          PrimaryIconButton(
            key: const Key("player_play"),
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onTap: notifier.toggle,
          ),
          IconButton(
            onPressed: notifier.next,
            icon: const Icon(Icons.skip_next),
            color: t.primary,
            iconSize: 30,
          ),
          IconButton(
            key: const Key("player_queue"),
            tooltip: "播放队列",
            onPressed: () => _openQueue(context, ref),
            icon: const Icon(Icons.queue_music_outlined),
            color: t.primary,
            iconSize: 24,
          ),
        ],
      ),
    );
  }

  // 播放队列 sheet（§3.4-5：插队/追加语义在队列引擎批次接数据操作）
  void _openQueue(BuildContext context, WidgetRef ref) {
    AppSheet.show(
      context,
      title: "播放队列 · ${ref.read(playbackProvider).queue.length} 首",
      child: SizedBox(
        height: 380,
        child: Consumer(
          builder: (context, sheetRef, _) {
            final pbState = sheetRef.watch(playbackProvider);
            final current = pbState.track;
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final track in pbState.queue)
                  SongListTile(
                    track: track,
                    playing: track.id == current?.id,
                    onTap: () {
                      sheetRef
                          .read(playbackProvider.notifier)
                          .play(track, queue: pbState.queue);
                      Navigator.of(context).pop();
                    },
                    onMorePressed: () =>
                        AppToast.show(context, "插队/移除在队列引擎批次接入"),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 动作行（喜欢 / 下载 / 稍后），位于进度条上方
class _ActionsRow extends ConsumerWidget {
  final bool liked;
  final VoidCallback onToggleLike;

  const _ActionsRow({required this.liked, required this.onToggleLike});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final actions = [
      (
        liked ? Icons.favorite : Icons.favorite_border,
        "喜欢",
        liked,
        onToggleLike,
        22.0,
      ),
      (
        Icons.download_outlined,
        "下载",
        false,
        () {
          final track = ref.read(playbackProvider).track;
          if (track != null) downloadTrack(context, track);
        },
        20.0,
      ),
      (
        Icons.add_rounded,
        "稍后",
        false,
        () {
          final track = ref.read(playbackProvider).track;
          if (track == null) return;
          TrackRepository().upsert(track);
          QueueRepository().append(track.id);
          ref.invalidate(queueTracksProvider);
          AppToast.show(context, "已加入播放队列");
        },
        22.0,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 4, 30, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label, active, onTap, size) in actions)
            ScaleTap(
              onTap: onTap,
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: size,
                    color: active ? t.primary : t.fgDim,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: active ? t.primary : t.fgDim,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 歌词视图（真 LRC）：滚动定位 + 校准 + 搜索替换/删除
/// 高频 position 只在本层订阅；自动匹配/手动搜索由 LyricController 负责
class _LyricView extends ConsumerStatefulWidget {
  const _LyricView({super.key});

  @override
  ConsumerState<_LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<_LyricView> {
  final _scroll = ScrollController();
  int _lastActive = -1;
  static const _rowExtent = 56.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _offsetLabel(int ms) => ms == 0
      ? "未校准"
      : "${ms > 0 ? "延后" : "提前"} ${(ms.abs() / 1000).toStringAsFixed(1)}s";

  /// 当前行变化时把该行滚到视口中央（手工滚动后仍会被下一次换行拉回）
  void _autoScroll(int active) {
    if (active < 0 || active == _lastActive) return;
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final target = (active * _rowExtent -
              position.viewportDimension / 2 +
              _rowExtent / 2)
          .clamp(0.0, position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _searchLyrics(Track track) async {
    final keyword = await AppDialog.input(
      context,
      title: "搜索歌词",
      hint: "歌名 / 歌手",
      initial: "${track.name} ${track.author}".trim(),
    );
    if (keyword == null || keyword.trim().isEmpty || !mounted) return;
    AppLoading.show(msg: "搜索歌词…");
    try {
      await ref
          .read(lyricControllerProvider.notifier)
          .searchCandidates(track, keyword.trim());
    } finally {
      AppLoading.dismiss();
    }
    if (!mounted) return;
    final candidates = ref.read(lyricControllerProvider).candidates;
    if (candidates.isEmpty) {
      AppToast.show(context, "没有找到歌词");
      return;
    }
    _showCandidates(track, candidates);
  }

  void _showCandidates(Track track, List<LyricCandidate> candidates) {
    AppSheet.show(
      context,
      title: "选择歌词 · ${candidates.length} 条",
      actions: [
        for (final candidate in candidates.take(8))
          AppSheetAction(
            icon: Icons.lyrics_outlined,
            label: "${candidate.title} · ${candidate.artist}",
            onTap: () => _previewAndApply(track, candidate),
          ),
      ],
    );
  }

  Future<void> _previewAndApply(
    Track track,
    LyricCandidate candidate,
  ) async {
    AppLoading.show(msg: "获取歌词…");
    final raw = await ref
        .read(lyricControllerProvider.notifier)
        .fetchCandidate(candidate);
    AppLoading.dismiss();
    if (!mounted) return;
    if (raw == null || raw.trim().isEmpty) {
      AppToast.show(context, "歌词获取失败，换一个试试");
      return;
    }
    final lines = parseLrc(raw);
    final ok = await AppDialog.show<bool>(
      context,
      title: "歌词预览",
      content: SizedBox(
        height: 260,
        child: lines.isEmpty
            ? const Center(child: Text("该候选没有可用时间轴"))
            : ListView.builder(
                itemCount: lines.length > 40 ? 40 : lines.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    lines[i].text,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("取消"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("应用"),
        ),
      ],
    );
    if (ok == true && mounted) {
      await ref.read(lyricControllerProvider.notifier).applyLyric(track, raw);
      if (mounted) AppToast.show(context, "已应用歌词");
    }
  }

  Future<void> _adjust(Track track, int deltaMs) async {
    await ref
        .read(lyricControllerProvider.notifier)
        .adjustOffset(track, deltaMs);
    if (!mounted) return;
    final offset = ref.read(lyricControllerProvider).offsetMs;
    AppToast.show(context, _offsetLabel(offset));
  }

  Future<void> _deleteLyric(Track track) async {
    final ok = await AppDialog.confirm(
      context,
      title: "删除歌词",
      message: "将从曲目移除已保存的歌词，可随时重新搜索。",
      danger: true,
      confirmText: "删除",
    );
    if (ok != true || !mounted) return;
    await ref.read(lyricControllerProvider.notifier).removeLyric(track);
    if (mounted) AppToast.show(context, "已删除歌词");
  }

  void _openTools(Track track) {
    AppSheet.show(
      context,
      title: "歌词设置",
      actions: [
        AppSheetAction(
          icon: Icons.fast_rewind_outlined,
          label: "歌词提前 0.5s",
          onTap: () => _adjust(track, -500),
        ),
        AppSheetAction(
          icon: Icons.fast_forward_outlined,
          label: "歌词延后 0.5s",
          onTap: () => _adjust(track, 500),
        ),
        AppSheetAction(
          icon: Icons.fast_rewind,
          label: "歌词提前 2s",
          onTap: () => _adjust(track, -2000),
        ),
        AppSheetAction(
          icon: Icons.fast_forward,
          label: "歌词延后 2s",
          onTap: () => _adjust(track, 2000),
        ),
        AppSheetAction(
          icon: Icons.restart_alt,
          label: "重置校准",
          onTap: () =>
              ref.read(lyricControllerProvider.notifier).resetOffset(track),
        ),
        AppSheetAction(
          icon: Icons.search,
          label: "搜索替换歌词",
          onTap: () => _searchLyrics(track),
        ),
        AppSheetAction(
          icon: Icons.delete_outline,
          label: "删除歌词",
          danger: true,
          onTap: () => _deleteLyric(track),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final track = ref.watch(playbackProvider.select((s) => s.track));
    final lyric = ref.watch(lyricControllerProvider);
    final positionMs = ref.watch(
      playbackProvider.select((s) => s.position.inMilliseconds),
    );
    if (track == null) return const SizedBox.shrink();

    final loading = lyric.loading || lyric.trackId != track.id;
    final active = activeLyricIndex(
      lyric.lines,
      Duration(milliseconds: positionMs),
      offsetMs: lyric.offsetMs,
    );
    if (!loading && lyric.lines.isNotEmpty) _autoScroll(active);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _offsetLabel(lyric.offsetMs),
                  style: TextStyle(fontSize: 12, color: t.fgDim),
                ),
              ),
              IconButton(
                key: const Key("lyric_search"),
                tooltip: "搜索歌词",
                onPressed: () => _searchLyrics(track),
                icon: Icon(Icons.search, size: 20, color: t.fgDim),
              ),
              if (lyric.lines.isNotEmpty)
                IconButton(
                  key: const Key("lyric_tools"),
                  tooltip: "歌词设置",
                  onPressed: () => _openTools(track),
                  icon: Icon(Icons.tune, size: 20, color: t.fgDim),
                ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: t.primary,
                  ),
                )
              : lyric.lines.isEmpty
                  ? EmptyState(
                      emoji: "🎵",
                      title: "暂无歌词",
                      subtitle: lyric.error ?? "可搜索并应用歌词",
                      action: GlassChip(
                        label: "搜索歌词",
                        onTap: () => _searchLyrics(track),
                      ),
                    )
                  : ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.22, 0.78, 1],
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                      ).createShader(bounds),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        itemExtent: _rowExtent,
                        itemCount: lyric.lines.length,
                        itemBuilder: (context, i) {
                          final line = lyric.lines[i];
                          final isActive = i == active;
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 26),
                              child: Text(
                                line.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isActive ? 20 : 15,
                                  fontWeight: isActive
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  height: 1.35,
                                  color: isActive ? t.primary : t.fgMute,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
