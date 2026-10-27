import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 空状态（原型 .empty：插画/emoji/线性图标 + 标题 + 引导文案）
/// [illustration] 优先于 [icon]/[emoji]：自绘主题色插画（empty_illustration.dart）
/// [icon] 优先于 [emoji]：需要统一风格时使用主题色线性图标
/// [compact] = 分区内嵌矮版（字号小一档）；间距全组件统一，不再分档
/// [action]  = 可选行动引导（如「去搜索」chip）
class EmptyState extends StatelessWidget {
  final String emoji;
  final IconData? icon;
  final Widget? illustration;
  final String title;
  final String? subtitle;
  final bool compact;
  final Widget? action;

  const EmptyState({
    super.key,
    this.emoji = "",
    this.icon,
    this.illustration,
    required this.title,
    this.subtitle,
    this.compact = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (illustration != null)
            illustration!
          else if (icon != null)
            Container(
              width: compact ? 54 : 72,
              height: compact ? 54 : 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.surface2,
                border: Border.all(color: t.hairline, width: 1),
              ),
              child: Icon(
                icon,
                size: compact ? 26 : 34,
                color: t.primary,
              ),
            )
          else
            Text(
              emoji,
              style: TextStyle(
                fontSize: compact ? 36 : 56,
                color: t.fgDim.withValues(alpha: 0.5),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w700,
              color: t.fg,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(fontSize: compact ? 12 : 12.5, color: t.fgDim),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite) {
          return Center(child: content);
        }
        return SizedBox(
          height: constraints.maxHeight,
          child: Center(child: content),
        );
      },
    );
  }
}
