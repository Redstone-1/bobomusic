import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";

import "../theme/aurora_tokens.dart";

/// 极光背景：三枚主题色系光斑缓慢漂移（原型 .aurora）
/// 用径向渐变代替 CSS blur(52px)，单 CustomPainter 绘制，成本可控
class AuroraBackground extends StatefulWidget {
  final Widget child;

  const AuroraBackground({super.key, required this.child});

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

    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _AuroraPainter(
          swatches: swatches,
          opacity: t.auroraOpacity,
          elapsed: _elapsed,
        ),
        child: widget.child,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final List<Color> swatches;
  final double opacity;
  final ValueNotifier<double> elapsed;

  _AuroraPainter({
    required this.swatches,
    required this.opacity,
    required this.elapsed,
  }) : super(repaint: elapsed);

  @override
  void paint(Canvas canvas, Size size) {
    // 三枚光斑定稿参数：直径 / 初始位置 / 漂移目标 / 周期秒（原型 22/26/30s）
    final blobs = [
      (340.0, const Offset(-120, -90), const Offset(60, 50), 22.0),
      (300.0, Offset(size.width - 190, 120), const Offset(-50, 60), 26.0),
      (360.0, Offset(-60, size.height - 240), const Offset(40, -50), 30.0),
    ];

    for (final (i, blob) in blobs.indexed) {
      final (d, base, drift, period) = blob;
      final p = (elapsed.value % period) / period;
      // 0→1→0 的平滑往返，等价原型 0%/50%/100% 关键帧漂移
      final k = 0.5 - 0.5 * math.cos(2 * math.pi * p);
      final center = base + drift * k + Offset(d / 2, d / 2);
      final rect = Rect.fromCircle(center: center, radius: d / 2);
      final color = swatches[i].withValues(alpha: opacity);

      canvas.drawCircle(
        center,
        d / 2,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.swatches != swatches || old.opacity != opacity;
}
