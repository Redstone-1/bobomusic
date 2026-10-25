import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 空状态（原型 .empty：emoji + 标题 + 引导文案）
/// [compact] = 分区内嵌矮版（歌单页/广场页的分区空态，非整页规格）
/// [action]  = 可选行动引导（如「去搜索」chip）
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
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20,
          vertical: compact ? 24 : 70,
        ),
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
            SizedBox(height: compact ? 8 : 14),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w700,
                color: t.fg,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: compact ? 4 : 6),
              Text(
                subtitle!,
                style: TextStyle(fontSize: compact ? 12 : 12.5, color: t.fgDim),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 12 : 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
