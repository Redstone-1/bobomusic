import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_progress_bar.dart";
import "../../core/widgets/origin_tag.dart";
import "../../core/widgets/scale_tap.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/mock/mock_data.dart";
import "../../data/models/track.dart";
import "mock_playback.dart";
import "spinning_cover.dart";

/// 全屏播放卡片（对齐原型 .player：封面模糊背景 + 黑胶 + seek + 控制区 + 动作行）
/// S1.4 mock 驱动；黑胶视图。歌词视图与播放队列 sheet 在批次 4
class PlayerCardPage extends ConsumerStatefulWidget {
  const PlayerCardPage({super.key});

  /// 仅开播（列表行点击用）：不弹卡，播放状态由迷你条承接
  static void start(BuildContext context, WidgetRef ref, Track track) {
    ref.read(mockPlaybackProvider.notifier).play(track);
  }

  /// 开播并以上滑转场打开播放卡（迷你条点击用；原型 .overlay 上滑 .5s）
  static void open(BuildContext context, WidgetRef ref, Track track) {
    start(context, ref, track);
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
  bool _liked = false; // mock：喜欢态卡片内本地维护，S3 接全局喜欢
  bool _showLyrics = false; // 歌词视图 / 黑胶视图切换（原型 toggleLyrics）

  @override
  Widget build(BuildContext context) {
    final pb = ref.watch(mockPlaybackProvider);
    final track = pb.track;
    // 理论不可达（打开前必 play）；防御：无曲直接回退
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: Stack(
        children: [
          _Backdrop(hue: track.coverHue ?? 212),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onClose: () => Navigator.of(context).pop()),
                // 黑胶区 / 歌词区（弹性占据，切换渐变过渡）
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _showLyrics
                        ? _LyricView(
                            key: const Key("player_lyrics"),
                            progress: pb.progress,
                          )
                        : Center(
                            key: const Key("player_disc"),
                            child: _VinylDisc(
                              hue: track.coverHue ?? 212,
                              letter: track.name.characters.first,
                              spinning: pb.playing,
                            ),
                          ),
                  ),
                ),
                _MetaRow(
                  track: track,
                  liked: _liked,
                  onToggleLike: () => setState(() => _liked = !_liked),
                ),
                const SizedBox(height: 18),
                _SeekRow(duration: track.duration ?? 240),
                _ControlsRow(),
                _ActionsRow(
                  showLyrics: _showLyrics,
                  onToggleLyrics: () =>
                      setState(() => _showLyrics = !_showLyrics),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景：封面色渐变（mock 无图；S3 换真封面 + ImageFilter.blur 60）+ 上下遮罩压回底色
class _Backdrop extends StatelessWidget {
  final int hue;

  const _Backdrop({required this.hue});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.64, -0.77),
                    end: const Alignment(0.64, 0.77),
                    colors: coverGradientColors(hue),
                  ),
                ),
              ),
            ),
          ),
          // 遮罩：顶部压暗 → 62% 处完全回到 bg（原型 .bgmask）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.62],
                  colors: [t.maskBg.withValues(alpha: 0.4), t.bg],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏：收起 / 正在播放 / 更多
class _TopBar extends StatelessWidget {
  final VoidCallback onClose;

  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
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
                  "啵啵音乐",
                  style: TextStyle(fontSize: 12, color: t.fgDim),
                ),
              ],
            ),
          ),
          GlassIconButton(
            icon: const Icon(Icons.more_horiz),
            onTap: () => AppToast.show(context, "更多操作（S4/S5 接入）"),
          ),
        ],
      ),
    );
  }
}

/// 黑胶唱片（原型 .disc：280 圆盘 + 同心纹 + 内嵌封面 22% + 中孔；播放中 14s 旋转）
class _VinylDisc extends StatelessWidget {
  final int hue;
  final String letter;
  final bool spinning;

  const _VinylDisc({
    required this.hue,
    required this.letter,
    required this.spinning,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return SpinningCover(
      spinning: spinning,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.bg2,
              border: Border.all(color: t.hairline, width: 1),
              boxShadow: [
                BoxShadow(
                  color: t.shadow,
                  blurRadius: 60,
                  offset: const Offset(0, 30),
                  spreadRadius: -24,
                ),
              ],
            ),
          ),
          // 同心纹（token 化的等效实现，替代原型 repeating-radial-gradient）
          for (final d in const [220.0, 186.0])
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.hairline, width: 1),
              ),
            ),
          // 内嵌封面（inset 22%）
          Container(
            width: 157,
            height: 157,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: const Alignment(-0.64, -0.77),
                end: const Alignment(0.64, 0.77),
                colors: coverGradientColors(hue),
              ),
              border: Border.all(color: t.hairlineStrong, width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 曲目信息 + 喜欢（D11：播放页显示音源标签）
class _MetaRow extends StatelessWidget {
  final Track track;
  final bool liked;
  final VoidCallback onToggleLike;

  const _MetaRow({
    required this.track,
    required this.liked,
    required this.onToggleLike,
  });

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
          IconButton(
            onPressed: onToggleLike,
            icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
            color: liked ? t.primary : t.fgDim,
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}

/// 时间 + seek 条（高频进度只重建本行）
class _SeekRow extends ConsumerWidget {
  final int duration;

  const _SeekRow({required this.duration});

  static String _fmt(int sec) =>
      "${sec ~/ 60}:${(sec % 60).toString().padLeft(2, "0")}";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final progress = ref.watch(mockPlaybackProvider.select((s) => s.progress));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          Text(
            _fmt((duration * progress).round()),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.fgDim),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AuroraProgressBar(
              value: progress,
              onChanged: ref.read(mockPlaybackProvider.notifier).seek,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmt(duration),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.fgDim),
          ),
        ],
      ),
    );
  }
}

/// 主控制区（模式 / 上一首 / 播放 / 下一首 / 队列）
class _ControlsRow extends ConsumerWidget {
  static const _modes = [
    (Icons.repeat_one, "单曲循环"),
    (Icons.queue_music, "列表循环"),
    (Icons.shuffle, "随机播放"),
    (Icons.repeat, "顺序播放"),
  ];

  const _ControlsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final pb = ref.watch(mockPlaybackProvider);
    final notifier = ref.read(mockPlaybackProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              notifier.cycleMode();
              AppToast.show(
                context,
                _modes[(pb.modeIndex + 1) % _modes.length].$2,
              );
            },
            icon: Icon(_modes[pb.modeIndex].$1),
            color: pb.modeIndex == 0 ? t.primary : t.fgMute,
            iconSize: 24,
          ),
          IconButton(
            onPressed: notifier.previous,
            icon: const Icon(Icons.skip_previous),
            color: t.fg,
            iconSize: 30,
          ),
          PrimaryIconButton(
            key: const Key("player_play"),
            icon: Icon(pb.playing ? Icons.pause : Icons.play_arrow),
            onTap: notifier.toggle,
          ),
          IconButton(
            onPressed: notifier.next,
            icon: const Icon(Icons.skip_next),
            color: t.fg,
            iconSize: 30,
          ),
          IconButton(
            key: const Key("player_queue"),
            onPressed: () => _openQueue(context, ref),
            icon: const Icon(Icons.queue_music_outlined),
            color: t.fg,
            iconSize: 24,
          ),
        ],
      ),
    );
  }

  // 播放队列 sheet（§3.4-5 语义：原「待播放列表」更名「播放队列」）
  // S1.4 仅展示 mock 队列与当前曲高亮；插队/追加/调序的数据操作在 S4 接队列引擎
  void _openQueue(BuildContext context, WidgetRef ref) {
    AppSheet.show(
      context,
      title: "播放队列 · ${mockTracks.length} 首",
      child: SizedBox(
        height: 380,
        child: Consumer(
          builder: (context, sheetRef, _) {
            final current = sheetRef.watch(mockPlaybackProvider).track;
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final track in mockTracks)
                  SongListTile(
                    track: track,
                    playing: track.id == current?.id,
                    onTap: () {
                      sheetRef.read(mockPlaybackProvider.notifier).play(track);
                      Navigator.of(context).pop();
                    },
                    onMorePressed: () =>
                        AppToast.show(context, "插队/移除在 S4 接队列引擎"),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 底部动作行（原型 .pactions：收藏 / 歌词 / 下载 / 稍后；歌词项为切换开关）
class _ActionsRow extends StatelessWidget {
  final bool showLyrics;
  final VoidCallback onToggleLyrics;

  const _ActionsRow({required this.showLyrics, required this.onToggleLyrics});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final actions = [
      (Icons.favorite_border, "收藏", false,
          () => AppToast.show(context, "收藏（S3 接全局喜欢）")),
      (Icons.lyrics, "歌词", showLyrics, onToggleLyrics),
      (Icons.download_outlined, "下载", false,
          () => AppToast.show(context, "下载在 S5 接入")),
      (Icons.add, "稍后", false,
          () => AppToast.show(context, "S4 接播放队列数据")),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 26),
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label, active, onTap) in actions)
            ScaleTap(
              onTap: onTap,
              child: Column(
                children: [
                  Icon(icon, size: 20, color: active ? t.primary : t.fgDim),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
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

/// 歌词视图（原型 .lyricbox：上下渐隐遮罩 + 居中行；当前行随播放进度推进）
/// mock 歌词按进度取整行走行；S4.4 换真歌词时间轴与滚动定位
class _LyricView extends StatelessWidget {
  final double progress;

  const _LyricView({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final active = (progress * mockLyrics.length).floor().clamp(
          0,
          mockLyrics.length - 1,
        );

    // 行数超出可视高度时转为滚动（矮视口防溢出），否则整列居中
    return LayoutBuilder(
      builder: (context, constraints) {
        return ShaderMask(
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
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, line) in mockLyrics.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Text(
                            line,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: active == i ? 21 : 17,
                              fontWeight:
                                  active == i ? FontWeight.w800 : FontWeight.w600,
                              height: 1.4,
                              color: active == i ? t.fg : t.fgMute,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
