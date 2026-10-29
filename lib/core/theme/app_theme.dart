import "package:flutter/material.dart";

import "app_palette.dart";

/// 由 10 色主题 × 明暗构建 ThemeData（token 经 ThemeExtension 注入）
/// Material 组件颜色统一从 ColorScheme 取，风格 A 专属值从 AuroraTokens 取
ThemeData buildAppTheme(AppThemeColor seed, Brightness brightness) {
  final t = buildAuroraTokens(seed, brightness);

  final scheme = ColorScheme.fromSeed(
    seedColor: t.primary,
    brightness: brightness,
  ).copyWith(
    primary: t.primary,
    onPrimary: t.primaryInk,
    secondary: t.primary,
    onSecondary: t.primaryInk,
    surface: t.bg2,
    onSurface: t.fg,
    onSurfaceVariant: t.fgDim,
    outline: t.hairlineStrong,
    outlineVariant: t.hairline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    extensions: [t],
  );
}
