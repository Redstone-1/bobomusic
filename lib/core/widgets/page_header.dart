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
/// [count] 为标题后的灰色小字补充（如「共 x 个」），与标题基线对齐；
/// [onTrailingTap] 非空时右侧说明可点（如「更多」→ 次级页），带按压缩放反馈
class SectionHeader extends StatelessWidget {
  final String title;
  final String? count;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      // 小字按标题中轴垂直居中，而非文字基线：基线对齐会让小字看起来偏上。
      // 标题组必须包在 Expanded 里吃满整行——若标题用 Flexible 参与 flex 分配，
      // 它用不掉的份额会堆到行尾，「更多/清空」就会离开右缘（标题越长偏得越多）。
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: t.fg,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    count!,
                    style: TextStyle(fontSize: 12, color: t.fgDim),
                  ),
                ],
              ],
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
