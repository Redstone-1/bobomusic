import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/scale_tap.dart";
import "../../data/models/track.dart";
import "../../origin_sdk/lyric/lrc.dart";
import "lyric_provider.dart";
import "playback_provider.dart";
import "player_card_page.dart";

/// 推入页（详情/搜索）通用外壳：内容铺满 + 底部迷你条（无播放自隐藏）
class MiniBarPage extends StatelessWidget {
  final Widget child;

  const MiniBarPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 14,
          right: 14,
          // 推入页无底部 Dock，留出下边距避免贴住屏幕底缘
          bottom: 12,
          child: const MiniPlayerBar(),
        ),
      ],
    );
  }
}

/// 迷你播放条：封面 + 歌名/单句歌词 + 播放状态波形 + 上一曲/播放/下一曲
/// 进度不再用底部横条，改为播放键外圈圆环；高频 position 只重建圆环和歌词行
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final track = ref.watch(playbackProvider.select((s) => s.track));
    final playing = ref.watch(playbackProvider.select((s) => s.playing));
    if (track == null) return const SizedBox.shrink();

    return ScaleTap(
      key: const Key("mini_player"),
      pressedScale: 0.98,
      onTap: () => PlayerCardPage.open(context, ref, track),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -22,
            ),
          ],
        ),
        // 玻璃本体：surface 只有 5.5% 透明度，必须配背景模糊才可读（原型 backdrop-filter）
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 68,
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: t.surface,
                border: Border.all(color: t.hairline, width: 1),
              ),
              child: Row(
                children: [
                  CoverPlaceholder(
                    cover: track.cover,
                    text: track.effectiveName,
                    size: 44,
                    radius: 13,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniCenter(track: track, playing: playing),
                  ),
                  const SizedBox(width: 4),
                  _MiniControls(playing: playing),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 中间信息：歌名 + 单句歌词（波形跟随播放状态）
class _MiniCenter extends StatelessWidget {
  final Track track;
  final bool playing;

  const _MiniCenter({required this.track, required this.playing});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.effectiveName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 3),
        _MiniLyricLine(track: track, playing: playing),
      ],
    );
  }
}

/// 当前单句歌词：自动加载歌词、随 position 切行，切行淡入上移
class _MiniLyricLine extends ConsumerStatefulWidget {
  final Track track;
  final bool playing;

  const _MiniLyricLine({required this.track, required this.playing});

  @override
  ConsumerState<_MiniLyricLine> createState() => _MiniLyricLineState();
}

class _MiniLyricLineState extends ConsumerState<_MiniLyricLine> {
  String? _requestedId;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _MiniLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) _ensureLoaded();
  }

  /// 迷你条独立出现（不经过播放卡）时也要触发歌词自动匹配
  void _ensureLoaded() {
    if (_requestedId == widget.track.id) return;
    _requestedId = widget.track.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(lyricControllerProvider.notifier).loadFor(widget.track);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final lyric = ref.watch(lyricControllerProvider);
    final positionMs = ref.watch(
      playbackProvider.select((s) => s.position.inMilliseconds),
    );

    final speed = ref.watch(playbackProvider.select((state) => state.speed));
    final loaded = lyric.trackId == widget.track.id;
    var text = "歌词匹配中…";
    var active = -1;
    if (loaded && !lyric.loading) {
      if (lyric.lines.isEmpty) {
        text = lyric.error ?? "暂无歌词";
      } else {
        active = activeLyricIndex(
          lyric.lines,
          Duration(milliseconds: positionMs),
          offsetMs: lyric.offsetMs,
        );
        final index = active < 0 ? 0 : active;
        text = active < 0 ? "…" : lyric.lines[index].text;
      }
    }

    return SizedBox(
      width: double.infinity,
      height: 15,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        // AnimatedSwitcher 默认 Stack 居中，会让短歌词先居中再跳回左侧；
        // 固定左对齐，切换只做淡入/上移
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _ScrollingLyricText(
          key: ValueKey(
            "${widget.track.id}:${active >= 0 ? active : -2}:$text",
          ),
          text: text,
          playing: widget.playing,
          speed: speed,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.2,
            color: active >= 0
                ? (widget.playing ? t.primary : t.fgDim)
                : t.fgMute,
          ),
        ),
      ),
    );
  }
}

/// 超长歌词横向滚动：起句短暂停顿 → 匀速滚到结尾（含尾距，不丢字）→
/// 停在末尾等下一句换行（所有者反馈：旧版匀速循环且末字被裁）。
/// 暂停即停、续播接着滚；只在组件内部动画，不重建迷你条。
class _ScrollingLyricText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool playing;
  final double speed;

  const _ScrollingLyricText({
    super.key,
    required this.text,
    required this.style,
    required this.playing,
    required this.speed,
  });

  @override
  State<_ScrollingLyricText> createState() => _ScrollingLyricTextState();
}

class _ScrollingLyricTextState extends State<_ScrollingLyricText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  /// 起句停 8%（给用户读开头），滚到 88% 停驻等下一句
  static const _scrollCurve = Interval(0.08, 0.88, curve: Curves.linear);

  /// 滚动结束后的尾距（尾字完整可见，不留死贴边）
  static const _trailingPad = 24.0;

  bool _overflow = false;
  double _distance = 0;

  Duration _scrollDuration() => Duration(
        milliseconds:
            ((4000 + _distance * 18).clamp(4000, 12000) / widget.speed).round(),
      );

  @override
  void didUpdateWidget(covariant _ScrollingLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      // 调整已在运行的动画时保留滚动位置，并按新倍速重新计算剩余时长。
      _controller.stop();
      _controller.duration = _scrollDuration();
    }
    _syncPlaying();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncPlaying() {
    if (!mounted || !_overflow) return;
    if (widget.playing) {
      if (!_controller.isAnimating) {
        _controller.forward(from: _controller.value);
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          // 与 Text 同缩放：系统字号非 1.0 时测量不偏小
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || painter.width <= maxWidth - _trailingPad) {
          _overflow = false;
          if (_controller.isAnimating) _controller.stop();
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: widget.style,
          );
        }
        _overflow = true;
        _distance = painter.width - maxWidth + _trailingPad;
        // 滚动时长随距离线性（约 55px/s），限制 4~12s
        _controller.duration = _scrollDuration();
        // build 内不动动画状态，帧末再启动/暂停（避免 build 期 setState）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncPlaying();
        });
        final anim = CurvedAnimation(parent: _controller, curve: _scrollCurve);
        return ClipRect(
          child: AnimatedBuilder(
            animation: anim,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_distance * anim.value, 0),
              child: child,
            ),
            // OverflowBox 解除子盒宽度约束：SizedBox 声明的全宽会被视口松约束
            // enforce 钳到视口宽，Text 就在布局期被裁掉尾巴——滚到头也出不来
            //（所有者 2026-10-29 反馈）。不用 UnconstrainedBox：它会把"子盒超父盒"
            // 当溢出上报，debug 画黄黑条纹跟字滚动；OverflowBox 正是为故意溢出
            // 设计，自身保持视口宽，ClipRect 仍负责裁剪。topLeft 锚定起始位置
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              // 宽度含尾距：滚到终点时尾字完整落在可视区内
              child: SizedBox(
                width: painter.width + _trailingPad,
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  style: widget.style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 上一曲 / 播放暂停（外圈进度环）/ 下一曲
class _MiniControls extends ConsumerWidget {
  final bool playing;

  const _MiniControls({required this.playing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final notifier = ref.read(playbackProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniIconButton(
          key: const Key("mini_prev"),
          icon: Icons.skip_previous,
          color: t.fgMute,
          onTap: notifier.previous,
        ),
        const SizedBox(width: 10),
        _MiniPlayButton(playing: playing),
        const SizedBox(width: 10),
        _MiniIconButton(
          key: const Key("mini_next"),
          icon: Icons.skip_next,
          color: t.fgMute,
          onTap: notifier.next,
        ),
      ],
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MiniIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

/// 播放键 + 极光进度环（进度 tick 只重建本组件）
class _MiniPlayButton extends ConsumerWidget {
  final bool playing;

  const _MiniPlayButton({required this.playing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final (positionMs, durationMs) = ref.watch(
      playbackProvider.select(
        (s) => (s.position.inMilliseconds, s.duration.inMilliseconds),
      ),
    );
    final progress = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;
    return Semantics(
      button: true,
      label: playing ? "暂停" : "播放",
      child: GestureDetector(
        key: const Key("mini_play"),
        behavior: HitTestBehavior.opaque,
        onTap: ref.read(playbackProvider.notifier).toggle,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  strokeCap: StrokeCap.round,
                  color: t.primary,
                  backgroundColor: t.surface2,
                ),
              ),
              Icon(
                playing ? Icons.pause : Icons.play_arrow,
                size: 22,
                color: t.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
