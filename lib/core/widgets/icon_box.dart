import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 行首图标盒（设置行 / 信息页卡片行共用）：38×38（与 GlassIconButton 同款）+
/// surface2 底 + radiusSm 圆角 + 主题色图标。原为两处页面私有组件（36 与 38
/// 两种规格、圆角 11 不在 token 档位），提取公共后统一（2026-11-07）
class IconBox extends StatelessWidget {
  final IconData icon;

  const IconBox({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radiusSm),
        color: t.surface2,
      ),
      child: Icon(icon, size: 19, color: t.primary),
    );
  }
}
