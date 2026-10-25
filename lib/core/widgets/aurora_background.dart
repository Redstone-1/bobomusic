import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";

import "../theme/aurora_tokens.dart";

/// 极光背景：三枚主题色系光斑缓慢漂移（原型 .aurora，画在内容底层）
///
/// 性能关键（S1.3 实证教训）：光斑是一次绘制的径向渐变图层，用 RepaintBoundary
/// 缓存位图，动画只改 Transform（合成器位移缓存层）——绝不能每帧重绘大面积渐变，
/// 否则上层 BackdropFilter 跟着每帧重模糊，模拟器/低端机直接卡到无法交互
class AuroraBackground extends StatefulWidget {
  final Widget child;

  /// false = 光斑定格（调试与性能对比用）
  final bool animated;

  const AuroraBackground({
    super.key,
    required this.child,
    this.animated = true,
  });

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _elapsed = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker =
        createTicker((e) => _elapsed.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    // 光斑色相：主题色 / +55 / -45（原型 nth-child 定义）
    final base = HSLColor.fromColor(t.glow);
    final swatches = [
      t.glow,
      base.withHue((base.hue + 55) % 360).toColor(),
      base.withHue((base.hue - 45 + 360) % 360).toColor(),
    ];

    // 三枚光斑定稿参数：直径 / 锚点(相对屏幕) / 漂移目标 / 周期秒（原型 22/26/30s）
    // 锚点含屏幕尺寸：右上光斑锚在宽-190，左下光斑锚在高-240
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final blobs = [
          (340.0, const Offset(-120, -90), const Offset(60, 50), 22.0),
          (300.0, Offset(w - 190, 120), const Offset(-50, 60), 26.0),
          (360.0, Offset(-60, h - 240), const Offset(40, -50), 30.0),
        ];

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.topLeft,
            children: [
              for (final (i, blob) in blobs.indexed)
                ValueListenableBuilder(
                  valueListenable: _elapsed,
                  builder: (context, sec, child) {
                    final (_, anchor, drift, period) = blob;
                    final p = widget.animated ? (sec % period) / period : 0.0;
                    // 0→1→0 平滑往返，等价原型 0%/50%/100% 关键帧
                    final k = 0.5 - 0.5 * math.cos(2 * math.pi * p);
                    return Transform.translate(
                      offset: anchor + drift * k,
                      child: child,
                    );
                  },
                  // RepaintBoundary 缓存渐变位图，Transform 仅更新图层矩阵
                  child: RepaintBoundary(
                    child: _Blob(
                      size: blob.$1,
                      color: swatches[i].withValues(alpha: t.auroraOpacity),
                    ),
                  ),
                ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

/// 单枚光斑：径向渐变圆，一次绘制后由 RepaintBoundary 缓存（定位由外层 Transform 负责）
class _Blob extends StatelessWidget {
  final double size;
  final Color color;

  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
