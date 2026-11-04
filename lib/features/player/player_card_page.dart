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
import "../../core/navigation/desktop_navigation.dart";
import "../../core/platform/app_platform.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/origin_tag.dart";
import "../../core/widgets/scale_tap.dart";
import "../../data/models/track.dart";
import "../../data/models/playlist.dart" show kBuiltinLikedPlaylist;
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/lyric/lrc.dart";
import "../../origin_sdk/lyric/lyric_types.dart";
import "../download/download_actions.dart";
import "../playlist/add_to_playlist_sheet.dart";
import "../playlist/playlists_provider.dart"
    show likedCountProvider, playlistDetailTracksProvider, queueEntriesProvider;
import "../playlist/track_edit_dialog.dart";
import "lyric_provider.dart";
import "open_bilibili.dart";
import "play_mode.dart";
import "playback_provider.dart";
import "playback_speed.dart";
import "playback_speed_sheet.dart";
import "sleep_timer_sheet.dart";
import "queue_sheet.dart";
import "comment_page.dart";

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
    if (ref.read(appPlatformProvider).usesDesktopLayout) {
      ref.read(desktopNavigationProvider.notifier).open(const DesktopDestination("player", "正在播放"));
      return;
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

class _PlayerCardPageState extends ConsumerState<PlayerCardPage>
    with SingleTickerProviderStateMixin {
  /// 喜欢态覆盖：打开/切歌时从库同步，卡内写库后即时更新；
  /// 播放状态里的 Track 是入队快照，不能直接作为心形依据
  bool? _likedOverride;

  @override
  void initState() {
    super.initState();
    // 滑动切歌动画：单一控制器驱动全程（前半滑出、切歌藏于预览全覆盖
    // 的一瞬、后半新内容滑入）。不可拆成 postFrame 链式两段动画——
    // 帧末回调里启动的第二段 ticker 首帧不推进时间，滑入会停在起点
    _swipeAnim.addListener(_onSwipeTick);
    _swipeAnim.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _swipeCommitting = false);
      }
    });
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

  @override
  void dispose() {
    _swipeAnim.dispose();
    super.dispose();
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
    // 喜欢列表可能正在后台：精确失效喜欢详情数据源，返回列表即同步
    ref.invalidate(playlistDetailTracksProvider(kBuiltinLikedPlaylist.id));
    // 写库期间可能已切歌：只更新当前曲目的覆盖
    if (ref.read(playbackProvider).track?.id == track.id) {
      setState(() => _likedOverride = newLiked);
    }
  }

  // ---- 滑动切歌（汽水式翻页，2026-11-01 定）----
  // 跟手：内容页随手指位移（视口高度倍数，负 = 上移），中间态不渲染
  // 邻曲信息；松手过阈值（视口高 18% 或快速轻扫）滑出并切歌、
  // 新内容自对侧滑入，未过阈值回弹。歌词区纵向滚动由列表自身消费，
  // 切歌手势只在非滚动区生效
  double _swipeFraction = 0;

  /// 松手动画进行中（期间忽略新的滑动手势）
  bool _swipeCommitting = false;
  bool _swipeCommitUp = false;
  bool _swipeSwitched = false;
  bool _swipeSpringing = false;
  double _swipeFrom = 0;
  double _swipeTarget = 0;
  late final AnimationController _swipeAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360), // 滑出 + 滑入全程
  );

  void _onSwipeStart(DragStartDetails details) {
    if (_swipeCommitting) return;
    _swipeFraction = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (_swipeCommitting) return;
    setState(() {
      _swipeFraction += details.delta.dy / MediaQuery.sizeOf(context).height;
    });
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_swipeCommitting) return;
    const kCommitDistance = 0.18; // 视口高度的 18%
    const kFlingVelocity = 900.0;
    final velocity = details.primaryVelocity ?? 0;
    final up = _swipeFraction < -kCommitDistance || velocity < -kFlingVelocity;
    final down = _swipeFraction > kCommitDistance || velocity > kFlingVelocity;
    // 未达阈值 / 队列不足两首（翻页无意义）：回弹不切歌
    if ((!up && !down) || ref.read(playbackProvider).queue.length <= 1) {
      _swipeSpringBack();
      return;
    }
    setState(() {
      _swipeCommitting = true;
      _swipeCommitUp = up;
      _swipeSwitched = false;
      _swipeSpringing = false;
      _swipeFrom = _swipeFraction;
      _swipeTarget = up ? -1.0 : 1.0;
    });
    _swipeAnim.forward(from: 0);
  }

  void _swipeSpringBack() {
    if (_swipeFraction == 0) return;
    setState(() {
      _swipeCommitting = true;
      _swipeSpringing = true;
      _swipeFrom = _swipeFraction;
    });
    _swipeAnim.forward(from: 0);
  }

  /// 全程动画：前半段当前页滑向目标（切歌动作藏在预览完全覆盖的一瞬），
  /// 后半段新内容自对侧滑入；回弹则全程从起点回 0
  void _onSwipeTick() {
    final t = _swipeAnim.value;
    double fraction;
    if (_swipeSpringing) {
      fraction = _swipeFrom * (1.0 - Curves.easeOutCubic.transform(t));
    } else if (!_swipeSwitched) {
      final out = Curves.easeOutCubic
          .transform((t / 0.5).clamp(0.0, 1.0).toDouble());
      fraction = _swipeFrom + (_swipeTarget - _swipeFrom) * out;
      if (t >= 0.5) {
        _swipeSwitched = true;
        if (_swipeCommitUp) {
          ref.read(playbackProvider.notifier).next();
        } else {
          ref.read(playbackProvider.notifier).previous();
        }
      }
    } else {
      final inn = Curves.easeOutCubic
          .transform(((t - 0.5) / 0.5).clamp(0.0, 1.0).toDouble());
      fraction = -_swipeTarget * (1.0 - inn);
    }
    setState(() => _swipeFraction = fraction);
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
    // 高频 position 不进本层，播放内容组件按需订阅各自状态。
    final track = ref.watch(playbackProvider.select((s) => s.track));
    // 理论不可达（打开前必 play）；防御：无曲直接回退
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    return Scaffold(
      // 背景与主壳一致（极光光球，所有者 2026-10-27 指定：不再单独设封面色背景）
      body: AuroraBackground(
        // 上滑下一曲 / 下滑上一曲（汽水式翻页）：内容随手指位移，松手过阈值
        // 滑出并切歌、新内容自对侧滑入，未过阈值回弹。歌词区纵向滚动由列表
        // 自身消费，切歌手势只在非滚动区生效；中间态不渲染任何邻曲信息
        // （所有者 2026-11-01 反馈）
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onSwipeStart,
          onVerticalDragUpdate: _onSwipeUpdate,
          onVerticalDragEnd: _onSwipeEnd,
          child: FractionalTranslation(
            translation: Offset(0, _swipeFraction),
            child: SafeArea(
              child: PlayerCardContent(
                track: track,
                liked: _likedOverride ?? track.liked,
                onToggleLike: () => _toggleLike(track),
                onHeaderAction: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机播放页与桌面右栏共用歌词、曲目信息和动作行；桌面播放控制由常驻底栏承接。
class PlayerCardContent extends ConsumerWidget {
  const PlayerCardContent(
      {super.key,
      required this.track,
      required this.liked,
      required this.onToggleLike,
      required this.onHeaderAction,
      this.sidePanel = false});

  final Track track;
  final bool liked;
  final VoidCallback onToggleLike;
  final VoidCallback onHeaderAction;
  final bool sidePanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration =
        ref.watch(playbackProvider.select((state) => state.duration));
    final durationSec =
        duration.inSeconds > 0 ? duration.inSeconds : track.duration ?? 240;
    return Column(children: [
      _TopBar(onClose: onHeaderAction, sidePanel: sidePanel),
      const Expanded(child: PlayerLyricsView(key: Key("player_lyrics"))),
      _MetaRow(track: track),
      const SizedBox(height: 12),
      _ActionsRow(track: track, liked: liked, onToggleLike: onToggleLike),
      if (!sidePanel) ...[
        // 进度块沿用 App 的上下留白与控制行间距。
        const SizedBox(height: 14),
        PlayerSeekBar(durationSec: durationSec),
        const _ControlsRow(),
      ],
      const SizedBox(height: 16),
    ]);
  }
}

/// 顶栏：收起 / 正在播放 / 更多（更多 = 加入歌单 / 编辑信息 / 定时关闭）
class _TopBar extends ConsumerWidget {
  final VoidCallback onClose;

  const _TopBar({required this.onClose, this.sidePanel = false});
  final bool sidePanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final sleep = ref.watch(playbackProvider.select(sleepTimerLabel));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      child: Row(
        children: [
          if (!sidePanel)
            Tooltip(
              message: "收起播放页",
              child: GlassIconButton(
                key: const Key("player_close"),
                icon: const Icon(Icons.keyboard_arrow_down),
                onTap: onClose,
              ),
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
          Tooltip(
            message: "更多",
            child: GlassIconButton(
              key: const Key("player_more"),
              icon: const Icon(Icons.more_horiz),
              onTap: () => _openMore(context, ref),
            ),
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
      actions: [
        if (track != null) ...[
          AppSheetAction(
            icon: Icons.library_add_outlined,
            label: "加入歌单",
            onTap: () => showAddToPlaylistSheet(context, ref, [track]),
          ),
          AppSheetAction(
            icon: Icons.edit_outlined,
            label: "编辑信息",
            onTap: () => showTrackEditDialog(context, ref, track),
          ),
        ],
        AppSheetAction(
          icon: Icons.timer_outlined,
          label: "定时关闭（${sleepTimerLabel(state)}）",
          onTap: () => showSleepTimerSheet(context, ref),
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
                  track.effectiveName,
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
                        track.effectiveAuthor,
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
class PlayerSeekBar extends ConsumerStatefulWidget {
  final int durationSec;

  const PlayerSeekBar({super.key, required this.durationSec, this.compact = false});
  final bool compact;

  @override
  ConsumerState<PlayerSeekBar> createState() => PlayerSeekBarState();
}

class PlayerSeekBarState extends ConsumerState<PlayerSeekBar> {
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

    if (widget.compact) {
      return Row(children: [
        Text(_fmt((widget.durationSec * shown).round()), style: labelStyle.copyWith(fontSize: 10)),
        const SizedBox(width: 10),
        Expanded(child: AuroraProgressBar(value: shown, height: 3, onPreviewChanged: _onPreview, onChanged: _commit)),
        const SizedBox(width: 10), Text(_fmt(widget.durationSec), style: labelStyle.copyWith(fontSize: 10)),
      ]);
    }

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

/// 动作行（喜欢 / 下载 / 稍后 / 评论 / 倍速 / B站），位于进度条上方
class _ActionsRow extends ConsumerWidget {
  final Track track;
  final bool liked;
  final VoidCallback onToggleLike;

  const _ActionsRow({
    required this.track,
    required this.liked,
    required this.onToggleLike,
  });

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
      // 评论仅网易/酷我源开放（其它音源无评论数据源，入口隐藏）
      if (track.origin == OriginType.netease || track.origin == OriginType.kuwo)
        (
          Icons.comment_outlined,
          "评论",
          false,
          () => CommentPage.open(context, track),
          22.0,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 4, 30, 4),
      child: Row(
        // 等宽单元决定中心间距，图标大小仅做光学校正；各源不超过 5 格
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
          // 去 B 站看视频：仅 B 站源展示（所有者 2026-11-01 定：放倍速后面）
          if (track.origin == OriginType.bili)
            Expanded(
              child: _PlayerActionButton(
                icon: Icons.smart_display_outlined,
                label: "B站",
                active: false,
                onTap: () => _openBilibili(context, track),
                iconSize: 24,
              ),
            ),
        ],
      ),
    );
  }

  /// 跳转 B 站视频页；打不开时提示（失败由 openBilibiliVideo 返回）
  Future<void> _openBilibili(BuildContext context, Track track) async {
    final opened = await openBilibiliVideo(track);
    if (!opened && context.mounted) {
      AppToast.show(context, "无法打开 B 站");
    }
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
class PlayerLyricsView extends ConsumerStatefulWidget {
  const PlayerLyricsView(
      {super.key, this.expanded = false, this.showTools = true});
  final bool expanded;
  final bool showTools;

  @override
  ConsumerState<PlayerLyricsView> createState() => PlayerLyricsViewState();
}

class PlayerLyricsViewState extends ConsumerState<PlayerLyricsView> {
  final _scroll = ScrollController();
  ({
    int active,
    double viewportHeight,
    double padding,
    double rowExtent,
    String? trackId,
    List<LyricLine> lines
  })? _lastScrollTarget;
  double get _rowExtent => widget.expanded ? 76 : 56;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 定位包含首尾留白；换歌词与缩放也重新对齐，普通进度更新保留手动滚动位置。
  void _autoScroll(
    int active,
    LyricState lyric, {
    required double padding,
    required double viewportHeight,
  }) {
    if (active < 0) return;
    final request = (
      active: active,
      viewportHeight: viewportHeight,
      padding: padding,
      rowExtent: _rowExtent,
      trackId: lyric.trackId,
      lines: lyric.lines
    );
    final previous = _lastScrollTarget;
    if (request == previous) return;
    _lastScrollTarget = request;
    final animate = previous != null &&
        previous.viewportHeight == viewportHeight &&
        previous.padding == padding &&
        previous.rowExtent == request.rowExtent &&
        previous.trackId == lyric.trackId &&
        identical(previous.lines, lyric.lines);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _lastScrollTarget != request) {
        return;
      }
      final position = _scroll.position;
      final target = (padding +
              active * request.rowExtent -
              position.viewportDimension / 2 +
              request.rowExtent / 2)
          .clamp(0.0, position.maxScrollExtent);
      if (!animate) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
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
    final desktop = DesktopContent.of(context);
    if (loading || lyric.lines.isEmpty) _lastScrollTarget = null;

    return Column(
      children: [
        if (widget.showTools) const PlayerLyricTools(),
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
                      action: const PlayerLyricTools(searchButtonOnly: true),
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
                      child: LayoutBuilder(builder: (context, constraints) {
                        // 桌面首尾各补半个视口，让第一句和最后一句也能停在正中。
                        final padding = desktop
                            ? ((constraints.maxHeight - _rowExtent) / 2)
                                .clamp(0.0, double.infinity)
                            : 36.0;
                        _autoScroll(active, lyric,
                            padding: padding,
                            viewportHeight: constraints.maxHeight);
                        return ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.symmetric(vertical: padding),
                          itemExtent: _rowExtent,
                          itemCount: lyric.lines.length,
                          itemBuilder: (context, i) {
                            final line = lyric.lines[i];
                            final isActive = i == active;
                            return InkWell(
                                onTap: () => ref
                                    .read(playbackProvider.notifier)
                                    .seek(line.time +
                                        Duration(milliseconds: lyric.offsetMs)),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 26),
                                    child: Text(
                                      line.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: widget.expanded
                                            ? (isActive ? 27 : 22)
                                            : (isActive ? 20 : 15),
                                        fontWeight: isActive
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        height: 1.35,
                                        color: isActive ? t.primary : t.fgMute,
                                      ),
                                    ),
                                  ),
                                ));
                          },
                        );
                      }),
                    ),
        ),
      ],
    );
  }
}

/// 搜索与校准工具独立于歌词滚动区，桌面展开页可把它放到左侧信息区。
class PlayerLyricTools extends ConsumerStatefulWidget {
  const PlayerLyricTools(
      {super.key, this.horizontalPadding = 26, this.searchButtonOnly = false});
  final double horizontalPadding;
  final bool searchButtonOnly;

  @override
  ConsumerState<PlayerLyricTools> createState() => _PlayerLyricToolsState();
}

class _PlayerLyricToolsState extends ConsumerState<PlayerLyricTools> {
  String _offsetLabel(int ms) => ms == 0
      ? "未校准"
      : "${ms > 0 ? "延后" : "提前"} ${(ms.abs() / 1000).toStringAsFixed(1)}s";

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

  /// 歌词工具面板：六项两列三行瓷贴（删除居第三行第二列），弹层高度
  /// 由七行列表压到瓷贴（所有者 2026-11-01 反馈弹层过高难交互；
  /// 滑杆方案对比后收益不足回退）；文案省略「歌词」前缀。
  /// 瓦片样式即全仓 AppSheet 操作网格的标准实现（2026-11-04 定稿）
  void _openTools(Track track) {
    // 校准方向约定（所有者 2026-11-03 指定）：右箭头 = 提前，
    // 左箭头 = 延后；与直觉相反，勿按常规语义改回
    AppSheet.show(context, actions: [
      AppSheetAction(
          icon: Icons.fast_rewind_outlined,
          label: "延后 0.5s",
          onTap: () => _adjust(track, 500)),
      AppSheetAction(
          icon: Icons.fast_forward_outlined,
          label: "提前 0.5s",
          onTap: () => _adjust(track, -500)),
      AppSheetAction(
          icon: Icons.fast_rewind,
          label: "延后 2s",
          onTap: () => _adjust(track, 2000)),
      AppSheetAction(
          icon: Icons.fast_forward,
          label: "提前 2s",
          onTap: () => _adjust(track, -2000)),
      AppSheetAction(
          icon: Icons.search,
          label: "搜索替换",
          onTap: () => _searchLyrics(track)),
      AppSheetAction(
          icon: Icons.delete_outline,
          label: "删除歌词",
          danger: true,
          onTap: () => _deleteLyric(track)),
    ]);
  }

  Future<void> _adjust(Track track, int deltaMs) async {
    await ref
        .read(lyricControllerProvider.notifier)
        .adjustOffset(track, deltaMs);
    if (!mounted) return;
    final offset = ref.read(lyricControllerProvider).offsetMs;
    AppToast.show(context, _offsetLabel(offset));
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final track = ref.watch(playbackProvider.select((state) => state.track));
    final lyric = ref.watch(lyricControllerProvider);
    if (track == null) return const SizedBox.shrink();
    if (widget.searchButtonOnly) {
      return GlassChip(label: "搜索歌词", onTap: () => _searchLyrics(track));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _offsetLabel(lyric.offsetMs),
              style: TextStyle(fontSize: 12, color: t.fgDim),
            ),
          ),
          // 宽度压成与顶栏 38×38 圆钮一致（高度仍 48 保行高），
          // 图标中心线与上方「更多」/「收起」精确同轴——左侧「未校准」
          // 视觉中心即落在该轴上，右侧保持同一竖线
          SizedBox(
            width: 38,
            child: IconButton(
              key: const Key("lyric_search"),
              tooltip: "搜索歌词",
              onPressed: () => _searchLyrics(track),
              icon: Icon(Icons.search, size: 20, color: t.fgDim),
            ),
          ),
          if (lyric.lines.isNotEmpty)
            SizedBox(
              width: 38,
              child: IconButton(
                key: const Key("lyric_tools"),
                tooltip: "歌词设置",
                onPressed: () => _openTools(track),
                icon: Icon(Icons.tune, size: 20, color: t.fgDim),
              ),
            ),
        ],
      ),
    );
  }
}
