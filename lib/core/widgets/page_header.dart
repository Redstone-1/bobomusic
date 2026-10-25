import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "scale_tap.dart";

/// 页面大标题（原型 .rowhead h1：28~30px 特粗 + 负字距；次级说明在其下）
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: t.fg,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: t.fgDim),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 区块标题行（原型 .sect：左标题 + 右说明）
/// [onTrailingTap] 非空时右侧说明可点（如「更多」→ 次级页），带按压缩放反馈
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: t.fg,
              ),
            ),
          ),
          if (trailing != null)
            ScaleTap(
              // 纯说明文案（计数等）不可点时保持原样，不包手势
              onTap: onTrailingTap,
              pressedScale: 0.9,
              child: Text(
                trailing!,
                style: TextStyle(fontSize: 12, color: t.fgDim),
              ),
            ),
        ],
      ),
    );
  }
}
