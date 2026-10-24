import "dart:ui" as ui;

import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 玻璃卡片：表面色 + 1px 发丝描边 + 圆角（原型 .settinggroup/.qi）
/// [frosted] 为真时叠加背景模糊与饱和度增益（原型 backdrop-filter）
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? radius;
  final bool frosted;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius,
    this.frosted = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final r = radius ?? t.radiusLg;

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: t.hairline, width: 1),
      ),
      // 局部变量承接可空 padding，促发类型提升
      child: _pad(child, padding),
    );

    if (frosted) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: BackdropFilter(
          // blur + saturate(160%)，与原型迷你条玻璃一致
          filter: ui.ImageFilter.compose(
            inner: ui.ImageFilter.blur(
              sigmaX: t.glassBlurSigma * 0.7,
              sigmaY: t.glassBlurSigma * 0.7,
            ),
            outer: ui.ColorFilter.matrix(_saturationMatrix(t.glassSaturation)),
          ),
          child: card,
        ),
      );
    }

    return card;
  }
}

/// 饱和度增益矩阵（saturation = 1 为原图）
List<double> _saturationMatrix(double s) {
  const rL = 0.2126, gL = 0.7152, bL = 0.0722;
  return [
    rL + (1 - rL) * s, gL * (1 - s), bL * (1 - s), 0, 0,
    rL * (1 - s), gL + (1 - gL) * s, bL * (1 - s), 0, 0,
    rL * (1 - s), gL * (1 - s), bL + (1 - bL) * s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

Widget _pad(Widget child, EdgeInsetsGeometry? padding) =>
    padding == null ? child : Padding(padding: padding, child: child);
