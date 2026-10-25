import "package:flutter/material.dart";

import "../theme/app_palette.dart";

/// 主题色选点（原型 .sw：40px 圆 + 选中白描边与 ✓）
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.color,
          border: Border.all(
            width: 2,
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: selected
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : null,
      ),
    );
  }
}
