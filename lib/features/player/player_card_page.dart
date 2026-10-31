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
import "../../data/models/track.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/lyric/lrc.dart";
import "../../origin_sdk/lyric/lyric_types.dart";
import "../download/download_actions.dart";
import "../playlist/playlists_provider.dart"
    show likedCountProvider, playlistDetailTracksProvider, queueEntriesProvider;
import "lyric_provider.dart";
import "open_bilibili.dart";
import "play_mode.dart";
import "playback_provider.dart";
import "playback_speed.dart";
import "playback_speed_sheet.dart";
import "sleep_timer_sheet.dart";
import "queue_sheet.dart";

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
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(
                  parent: animation, curve: t.motionCurveEmphasized)),
          child: child,
        ),
      ),
    );
  }

  @override
  ConsumerState<PlayerCardPage> createState() => _PlayerCardPageState();
}

class _PlayerCardPageState extends ConsumerState<PlayerCardPage> {
  /// 喜欢态覆盖：打开/切歌时从库同步，卡内写库后即时更新；
  /// 播放状态里的 Track 是入队快照，不能直接作为心形依据
  bool? _likedOverride;

  @override
  void initState() {
    super.initState();
    // 打开播放卡即预加载歌词（库内有则直接显示；无则自动匹配三顺位）
    final track = ref.read(playbackProvider).track;
    if (track != null) {
      Future.microtask(() {
        if (mounted) {
          ref.read(lyricControllerProvider.notifier).loadFor(track);
          _syncLikedFromDb(track);
        }
      });
    }
  }

  /// 快照上的 liked 可能已被别处改写：以库态校正，避免取消喜欢后重开仍是红心
  Future<void> _syncLikedFromDb(Track track) async {
    final stored = await TrackRepository().getById(track.id);
    if (!mounted) return;
    if (ref.read(playbackProvider).track?.id != track.id) return;
    // 卡内已操作过：以用户刚才的操作为准，避免回退
    if (_likedOverride != null) return;
    setState(() => _likedOverride = stored?.liked);
  }

  /// 喜欢/取消喜欢：心形与动作行共用同一份库态/本地覆盖
  Future<void> _toggleLike(Track track) async {
    final newLiked = !(_likedOverride ?? track.liked);
    // 先落库再失效数据源，避免列表重读抢在写库前拿到旧库态
    await TrackRepository().setLiked(track.id, newLiked);
    if (!mounted) return;
    ref.invalidate(likedCountProvider);
    // 喜欢列表可能正在后台：失效共享数据源，返回列表即同步
    ref.invalidate(playlistDetailTracksProvider);
    // 写库期间可能已切歌：只更新当前曲目的覆盖
    if (ref.read(playbackProvider).track?.id == track.id) {
      setState(() => _likedOverride = newLiked);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 切歌时重新加载歌词（保持同一播放卡内的歌词跟随），
    // 并清掉上一曲的喜欢覆盖，随后从库同步新曲喜欢态（防跨曲残留）
    ref.listen(playbackProvider.select((s) => s.track), (_, next) {
      if (next != null) {
        setState(() => _likedOverride = null);
        ref.read(lyricControllerProvider.notifier).loadFor(next);
        _syncLikedFromDb(next);
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
    final durationSec =
        duration.inSeconds > 0 ? duration.inSeconds : track.duration ?? 240;

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
              // 进度块（条+时间）上下留白对称：上 14 / 下 14（_ControlsRow 顶部
              // padding），条与时间间距 8——整块节奏一致（所有者 2026-10-28 定）
              const SizedBox(height: 14),
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
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: t.fg),
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
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: t.fg),
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

/// 进度条 + 下方时间（高频进度只重建本行；seek 按真时长换算秒）
/// 所有者 2026-10-28 定：时间移到条下方两侧，条独占整行且粗细 4→3——
/// 数字不再与条挤占宽度（此前的行内槽位方案曾把数字挤到换行）
/// 拖拽三段式（2026-10-31）：拖动中只上报预览、不发 seek；松手提交一次，
/// 提交后钉住预览值直到引擎位置追上（或 2s 超时），旧位置事件不再把进度拉回
class _SeekRow extends ConsumerStatefulWidget {
  final int durationSec;

  const _SeekRow({required this.durationSec});

  @override
  ConsumerState<_SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends ConsumerState<_SeekRow> {
  static String _fmt(int sec) =>
      "${sec ~/ 60}:${(sec % 60).toString().padLeft(2, "0")}";

  /// 拖拽预览值（含提交后的钉住期）：期间显示它而非引擎位置
  double? _preview;
  DateTime _previewDeadline = DateTime.fromMillisecondsSinceEpoch(0);

  void _onPreview(double fraction) {
    setState(() {
      _preview = fraction;
      _previewDeadline = DateTime.now().add(const Duration(seconds: 2));
    });
  }

  void _commit(double fraction) {
    // 先钉住预览再 seek：引擎完成前的 position 事件不会把进度条拉回旧值
    _onPreview(fraction);
    ref.read(playbackProvider.notifier).seek(
          Duration(seconds: (widget.durationSec * fraction).round()),
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final (positionMs, durationMs) = ref.watch(
      playbackProvider.select(
        (s) => (s.position.inMilliseconds, s.duration.inMilliseconds),
      ),
    );
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
    var shown = progress;
    final preview = _preview;
    if (preview != null) {
      // 引擎位置追上预览（留 1.1s 容差覆盖秒级取整）或超时后交还真实进度
      final caught =
          durationMs <= 0 || (progress - preview).abs() * durationMs < 1100;
      if (caught || DateTime.now().isAfter(_previewDeadline)) {
        _preview = null;
      } else {
        shown = preview;
      }
    }
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: t.fgDim,
    );

    return Padding(
      // 34 = 控制行左右 26 + IconButton 视觉内边 8：进度块与按钮区等宽对齐
      // （26 全宽曾被所有者指"超出按钮区不少，不和谐"）
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuroraProgressBar(
            value: shown,
            height: 3,
            onPreviewChanged: _onPreview,
            onChanged: _commit,
          ),
          // 进度条自带 28px 命中区（视觉轨道仍 3px 居中），不再另留 8px 间距
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt((widget.durationSec * shown).round()),
                  style: labelStyle),
              Text(_fmt(widget.durationSec), style: labelStyle),
            ],
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
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 8),
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
            size: 64,
            // 三角放大（默认 0.32 在 64 径里偏小，所有者 2026-10-29 反馈）
            iconScale: 0.44,
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
            onPressed: () => showPlaybackQueueSheet(context),
            icon: const Icon(Icons.queue_music_outlined),
            color: t.primary,
            iconSize: 24,
          ),
        ],
      ),
    );
  }

}

/// 动作行（喜欢 / 下载 / 稍后 / 倍速），位于进度条上方
class _ActionsRow extends ConsumerWidget {
  final bool liked;
  final VoidCallback onToggleLike;

  const _ActionsRow({required this.liked, required this.onToggleLike});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        23.0,
      ),
      (
        Icons.playlist_play_rounded,
        "稍后",
        false,
        () async {
          final track = ref.read(playbackProvider).track;
          if (track == null) return;
          try {
            await TrackRepository().upsert(track);
            // 稍后 = 插到待播放队首；完成写入后再刷新，避免先查到旧列表。
            await QueueRepository().insertNext(track.id);
            if (!context.mounted) return;
            ref.invalidate(queueEntriesProvider);
            AppToast.show(context, "已稍后播放 · 当前歌曲结束后播出");
          } catch (e) {
            print("加入待播放失败：$e");
            if (context.mounted) AppToast.show(context, "加入待播放失败，请重试");
          }
        },
        // 列表播放字形留白较多，单独放大补齐可见尺寸，不改变对齐槽位。
        30.0,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 4, 30, 4),
      child: Row(
        // 四个等宽单元决定中心间距，图标大小仅做光学校正。
        children: [
          for (final (icon, label, active, onTap, size) in actions)
            Expanded(
              child: _PlayerActionButton(
                icon: icon,
                label: label,
                active: active,
                onTap: onTap,
                iconSize: size,
              ),
            ),
          const Expanded(child: _SpeedAction()),
        ],
      ),
    );
  }
}

/// 动作行共用图标槽与文字行高，避免新增入口再次带入不同的布局规则。
class _PlayerActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double iconSize;
  final String? semanticLabel;

  const _PlayerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.iconSize = 24,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AuroraTokens.of(context);
    final color = active ? tokens.primary : tokens.fgDim;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: ScaleTap(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(icon, size: iconSize, color: color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 倍速值独立订阅，不随高频进度重建整个动作行。
class _SpeedAction extends ConsumerWidget {
  const _SpeedAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackProvider.select((state) => state.speed));
    final speedLabel = playbackSpeedLabel(speed);
    return _PlayerActionButton(
      key: const Key("player_speed"),
      icon: Icons.speed_rounded,
      label: "倍速",
      active: speed != 1.0,
      semanticLabel: "播放速度：$speedLabel",
      onTap: () => showPlaybackSpeedSheet(context),
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
                      asset: "assets/illustrations/empty_music.svg",
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
