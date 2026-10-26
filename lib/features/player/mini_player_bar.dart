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
                    text: track.name,
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
          track.name,
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

/// 超长歌词横向滚动；不溢出时静止显示。只在组件内部动画，不重建迷你条。
class _ScrollingLyricText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool playing;

  const _ScrollingLyricText({
    super.key,
    required this.text,
    required this.style,
    required this.playing,
  });

  @override
  State<_ScrollingLyricText> createState() => _ScrollingLyricTextState();
}

class _ScrollingLyricTextState extends State<_ScrollingLyricText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _ScrollingLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || painter.width <= maxWidth) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: widget.style,
          );
        }

        final distance = painter.width - maxWidth + 8;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-distance * _controller.value, 0),
                child: child,
              );
            },
            child: SizedBox(
              width: painter.width,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
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
