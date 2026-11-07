import "package:flutter/material.dart";

import "../theme/app_palette.dart";
import "../theme/aurora_tokens.dart";

/// 进度条（原型 .bar：5px 圆角轨道 + 主题色渐变填充 + glow 辉光 + 白色拖点）
/// [onChanged] 为空时是纯展示态；非空时支持点按与水平拖动定位（播放页 seek 用）：
/// 拖动过程只经 [onPreviewChanged] 上报预览值（调用方回填 [value] 显示），
/// 松手才回调一次 [onChanged]——拖拽期间不直发 seek，引擎旧位置不再把拖点拉回
/// （真机"拖不动/像被节流"的根因）。
/// [showThumb] 为 false 时隐藏拖点（下载页细进度线用）；拖点/辉光超出轨道高度，
/// 显示拖点时放开 Stack 裁剪，否则圆点会被裁成横线（真机截图实证）
class AuroraProgressBar extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onPreviewChanged;
  final double height;
  final bool showThumb;

  const AuroraProgressBar({
    super.key,
    required this.value,
    this.onChanged,
    this.onPreviewChanged,
    this.height = 5,
    this.showThumb = true,
  });

  @override
  State<AuroraProgressBar> createState() => _AuroraProgressBarState();
}

class _AuroraProgressBarState extends State<AuroraProgressBar> {
  double _fractionOf(Offset localPosition, double width) =>
      (localPosition.dx / width).clamp(0.0, 1.0);

  /// 最近一次拖动位置：dragEnd 事件不带落点，松手提交用它
  double? _lastDragFraction;

  void _preview(Offset localPosition, double width) {
    _lastDragFraction = _fractionOf(localPosition, width);
    widget.onPreviewChanged?.call(_lastDragFraction!);
  }

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
          clipBehavior: widget.showThumb ? Clip.none : Clip.hardEdge,
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
                    color: t.thumbColor,
                    boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                ),
              ),
          ],
        );

        if (widget.onChanged == null) return bar;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) =>
              widget.onChanged!(_fractionOf(d.localPosition, width)),
          onHorizontalDragStart: (d) => _preview(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _preview(d.localPosition, width),
          onHorizontalDragEnd: (_) {
            final fraction = _lastDragFraction;
            _lastDragFraction = null;
            if (fraction != null) widget.onChanged!(fraction);
          },
          // 视觉轨道只有 [height] 高，热区扩到 28px（真机反馈"点不动"）
          child: SizedBox(
            height: 28,
            child: Center(child: bar),
          ),
        );
      },
    );
  }
}
