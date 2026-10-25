import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

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
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

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
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, color: t.fgDim),
            ),
        ],
      ),
    );
  }
}
