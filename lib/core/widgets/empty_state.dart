import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 空状态（原型 .empty：emoji + 标题 + 引导文案）
/// [compact] = 分区内嵌矮版（字号小一档）；间距全组件统一，不再分档
/// [action]  = 可选行动引导（如「去搜索」chip）
///
/// 垂直居中只在容器高度有界时生效（Expanded/SizedBox/Stack Positioned.fill
/// 撑满容器居中）；列表项等高度无界场景保持自然高度，不撑高、不影响父布局。
/// 整页型空态要"列表可视区居中"由调用方用 Stack + Positioned.fill 覆盖实现。
class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final bool compact;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.emoji,
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
