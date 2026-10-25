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

    // 三枚光斑参数：直径 / 锚点 / Y漂移目标 / 漂移周期 / 呼吸周期（秒）
    // 基于原型（375 宽稿 340/300/360、锚 -120,-90 等）三重调整（所有者定）：
    // ①直径与锚点整体 ×1.5（构图比例不变，溢出角落的份额保持原型）；
    // ②漂移幅度 ×2.6 增大运动范围，仍只沿 Y 轴（X 坐标全程不动）；
    // ③新增呼吸（绕中心 ±12% 缩放，周期 9/11/13s 错相，与漂移独立）
    // 响应式：全量按 s = w/375 等比缩放；贴底语义保留（③锚 y 含 h）
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // 高度用窗口全屏尺寸（MediaQuery 不随输入法压缩）：键盘弹出/收起
        // 光斑纹丝不动，被压缩掉的底部区域由 ClipRect 裁剪（本就在键盘下方）
        final h = MediaQuery.sizeOf(context).height;
        final s = w / 375;
        final blobs = [
          (510.0 * s, Offset(-180 * s, -135 * s), Offset(0, 130 * s), 22.0, 9.0),
          (450.0 * s, Offset(w - 285 * s, 180 * s), Offset(0, 160 * s), 26.0, 11.0),
          (540.0 * s, Offset(-90 * s, h - 360 * s), Offset(0, -130 * s), 30.0, 13.0),
        ];

        return ClipRect(
          child: Stack(
            // loose：光斑保持自身直径。曾用 expand，tight 约束把 _Blob 的
            // SizedBox 压成全屏大小，圆变成"全屏内切圆"、直径参数完全失效
            fit: StackFit.loose,
            alignment: Alignment.topLeft,
            children: [
              for (final (i, blob) in blobs.indexed)
                // OverflowBox 解除 Stack 约束：光球直径可超视口（角落溢出式
                // 构图），动画仍由 Transform 驱动、不触发 relayout
                OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: ValueListenableBuilder(
                    valueListenable: _elapsed,
                    builder: (context, sec, child) {
                      final (_, anchor, drift, period, breathePeriod) = blob;
                      final p = widget.animated ? (sec % period) / period : 0.0;
                      // 0→1→0 平滑往返，等价原型 0%/50%/100% 关键帧
                      final k = 0.5 - 0.5 * math.cos(2 * math.pi * p);
                      // 呼吸：-1→1→-1 平滑往返，映射 ±12% 缩放（相位错开 1/4 周期）
                      final bq = widget.animated
                          ? ((sec + breathePeriod / 4) % breathePeriod) / breathePeriod
                          : 0.25;
                      final breathe =
                          1 + 0.12 * math.sin(2 * math.pi * bq - math.pi / 2);
                      return Transform.translate(
                        offset: anchor + drift * k,
                        // scale 与 translate 同为合成器矩阵操作，
                        // 不触发 RepaintBoundary 缓存位图重绘
                        child: Transform.scale(scale: breathe, child: child),
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
                ),
              // 内容层单独撑满（loose 下不再自动 expand）
              ConstrainedBox(
                constraints: constraints,
                child: widget.child,
              ),
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
