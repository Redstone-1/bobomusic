import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "scale_tap.dart";

/// 圆形玻璃图标按钮（原型 .iconbtn：38×38，表面色 + 发丝描边）
class GlassIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final double size;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.surface,
          border: Border.all(color: t.hairline, width: 1),
        ),
        child: IconTheme(
          data: IconThemeData(color: t.fg, size: size * 0.47),
          child: icon,
        ),
      ),
    );
  }
}

/// 主题色圆形按钮（原型 .playbig：primary 底 + primary-ink 前景 + glow 辉光投影）
class PrimaryIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final double size;

  /// 前景图标占按钮直径的比例（原型 0.32；播放卡播放三角放大用 0.44）
  final double iconScale;

  const PrimaryIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 74,
    this.iconScale = 0.32,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.primary,
          boxShadow: [
            // 原型 box-shadow: 0 16px 36px -14px var(--glow)
            BoxShadow(
              color: t.glow,
              blurRadius: 36,
              offset: const Offset(0, 16),
              spreadRadius: -14,
            ),
          ],
        ),
        child: IconTheme(
          data: IconThemeData(color: t.primaryInk, size: size * iconScale),
          child: icon,
        ),
      ),
    );
  }
}

/// 胶囊标签/筛选片（原型 .chip：选中态 primary 底 + primary-ink）
class GlassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// 等分拉伸场景（音源选择器）可传紧凑 padding，默认内容自适应
  final EdgeInsetsGeometry? padding;

  const GlassChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return ScaleTap(
      onTap: onTap,
      pressedScale: 0.95,
      child: Container(
        // 文字居中：胶囊被 Expanded 等分拉伸时（音源选择器）保持居中；
        // 内容自适应宽度的常规用法下无视觉差异
        alignment: Alignment.center,
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? t.primary : t.surface,
          border: selected ? null : Border.all(color: t.hairline, width: 1),
        ),
        child: Text(
          label,
          // 胶囊标签单行是硬约束：等分拉伸下宽度不足时也不折行
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? t.primaryInk : t.fgDim,
          ),
        ),
      ),
    );
  }
}
