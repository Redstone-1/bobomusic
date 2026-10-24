import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";

import "../theme/aurora_tokens.dart";

/// 播放中均衡器动效（原型 .eq：3 柱，0.9s 往复，相位差 .15s/.35s）
/// 列表行「正在播放」标识，播放页也可复用
class EqBars extends StatefulWidget {
  final Color? color;
  final double height;

  const EqBars({super.key, this.color, this.height = 14});

  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
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
    final color = widget.color ?? AuroraTokens.of(context).primary;
    return ValueListenableBuilder(
      valueListenable: _elapsed,
      builder: (context, t, _) => CustomPaint(
        size: Size(13, widget.height),
        painter: _EqPainter(elapsed: t, color: color, height: widget.height),
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  final double elapsed;
  final Color color;
  final double height;

  _EqPainter({required this.elapsed, required this.color, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0, gap = 2.0;
    // 三柱相位：0 / .15s / .35s（原型 animation-delay）
    const phases = [0.0, 0.15, 0.35];

    for (final (i, phase) in phases.indexed) {
      final p = ((elapsed + phase) % 0.9) / 0.9;
      final k = 0.5 - 0.5 * math.cos(2 * math.pi * p);
      final h = 4.0 + (height - 4.0) * k;
      final left = i * (barWidth + gap);
      final rect = Rect.fromLTWH(
        left,
        height - h,
        barWidth,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) =>
      old.elapsed != elapsed || old.color != color;
}
