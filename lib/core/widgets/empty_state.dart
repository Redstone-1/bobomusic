import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 空状态（原型 .empty：emoji + 标题 + 引导文案）
/// [compact]   = 分区内嵌矮版（歌单页/广场页的分区空态，非整页规格）
/// [action]    = 可选行动引导（如「去搜索」chip）
/// [spacious]  = 宽松版（仅广场收藏合集等大分区块）：行距加大 + 顶部留白下移，
///               与普通 compact 并存，避免影响其他分区空态
class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final bool compact;
  final Widget? action;
  final bool spacious;

  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.compact = false,
    this.action,
    this.spacious = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    // compact 默认行距偏紧；宽松版整体加大并靠不对称内边距下移
    final gapIconTitle = spacious ? 14.0 : compact ? 8.0 : 14.0;
    final gapTitleSub = spacious ? 8.0 : compact ? 4.0 : 6.0;
    final gapSubAction = spacious ? 18.0 : compact ? 12.0 : 14.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20,
          vertical: spacious ? 44 : compact ? 24 : 70,
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
            SizedBox(height: gapIconTitle),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w700,
                color: t.fg,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: gapTitleSub),
              Text(
                subtitle!,
                style: TextStyle(fontSize: compact ? 12 : 12.5, color: t.fgDim),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: gapSubAction),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
