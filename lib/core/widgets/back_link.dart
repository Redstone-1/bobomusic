import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "scale_tap.dart";
import "desktop_content.dart";

/// 返回行（原型 .backlink：‹ 返回，次级文字色）
class BackLink extends StatelessWidget {
  final VoidCallback? onTap;

  const BackLink({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (DesktopContent.of(context)) return const SizedBox.shrink();
    final t = AuroraTokens.of(context);
    return ScaleTap(
      pressedScale: 0.95,
      onTap: onTap ?? () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_ios_new, size: 15, color: t.fgDim),
            const SizedBox(width: 8),
            Text(
              "返回",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.fgDim),
            ),
          ],
        ),
      ),
    );
  }
}
