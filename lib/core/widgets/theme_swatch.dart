import "package:flutter/material.dart";

import "../theme/app_palette.dart";

/// 主题色选点：40px 圆、选中描边与勾选标记。
class ThemeSwatch extends StatelessWidget {
  final AppThemeColor color;
  final bool selected;
  final VoidCallback onTap;

  const ThemeSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = buildAuroraTokens(color, Theme.of(context).brightness);
    // 中性色随明暗显示实际强调色，避免深黑预览与灰色主题效果不符。
    final preview =
        color == AppThemeColor.deepSpaceBlack ? tokens.primary : color.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: preview,
          border: Border.all(
            width: 2,
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: selected
            ? Icon(Icons.check, size: 15, color: tokens.primaryInk)
            : null,
      ),
    );
  }
}
