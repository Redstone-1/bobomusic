import "package:flutter/material.dart";

import "../theme/app_palette.dart";
import "../theme/aurora_tokens.dart";

/// 进度条（原型 .bar：5px 圆角轨道 + 主题色渐变填充 + glow 辉光 + 白色拖点）
/// [onChanged] 为空时是纯展示态；非空时支持点按与水平拖动定位（播放页 seek 用）
/// [showThumb] 为 false 时隐藏拖点（迷你条底部细进度线用）
class AuroraProgressBar extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double height;
  final bool showThumb;

  const AuroraProgressBar({
    super.key,
    required this.value,
    this.onChanged,
    this.height = 5,
    this.showThumb = true,
  });

  @override
  State<AuroraProgressBar> createState() => _AuroraProgressBarState();
}

class _AuroraProgressBarState extends State<AuroraProgressBar> {
  double _fractionOf(Offset localPosition, double width) =>
      (localPosition.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final value = widget.value.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbSize = widget.height * 2.6;

        final bar = Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 轨道
            Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height),
                color: t.hairline,
              ),
            ),
            // 填充（渐变 + glow）
            Container(
              width: (width * value).clamp(widget.showThumb ? thumbSize / 2 : 0, width),
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height),
                gradient: LinearGradient(colors: progressGradientColors(t.primary)),
                boxShadow: [BoxShadow(color: t.glow, blurRadius: 14)],
              ),
            ),
            // 白色拖点（原型 13px，带投影）
            if (widget.showThumb)
              Positioned(
                left: (width * value - thumbSize / 2).clamp(0.0, width - thumbSize),
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                ),
              ),
          ],
        );

        if (widget.onChanged == null) return bar;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onChanged!(_fractionOf(d.localPosition, width)),
          onHorizontalDragUpdate: (d) =>
              widget.onChanged!(_fractionOf(d.localPosition, width)),
          child: bar,
        );
      },
    );
  }
}
