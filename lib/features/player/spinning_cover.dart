import "package:flutter/material.dart";

/// 旋转封面（原型 .disc/.mini .cv：黑胶 14s / 迷你条 8s 线性旋转，仅播放中转）
/// 性能与极光同款：RepaintBoundary 缓存位图，动画只改图层旋转矩阵，零重绘
class SpinningCover extends StatefulWidget {
  final Widget child;
  final bool spinning;
  final Duration period;

  const SpinningCover({
    super.key,
    required this.child,
    required this.spinning,
    this.period = const Duration(seconds: 14),
  });

  @override
  State<SpinningCover> createState() => _SpinningCoverState();
}

class _SpinningCoverState extends State<SpinningCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(SpinningCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning != oldWidget.spinning) {
      // 暂停停在当前角度，恢复从原角度继续
      widget.spinning ? _controller.repeat() : _controller.stop();
    }
    if (widget.period != oldWidget.period) {
      _controller.duration = widget.period;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _controller.value * 2 * 3.14159265,
        child: child,
      ),
      child: RepaintBoundary(child: widget.child),
    );
  }
}
