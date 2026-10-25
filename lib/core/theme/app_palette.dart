import "dart:ui" show Brightness;

import "package:flutter/painting.dart";

import "aurora_tokens.dart";

/// 8 种主题色（视觉定稿见 prototype/style-a-aurora，COLORS/COLOR_NAMES）
/// 自然绿置首（默认主题色，所有者 2026-10-25 指定）
enum AppThemeColor {
  natureGreen(0xFF2EC4B6, "自然绿"),
  sunsetRed(0xFFFF3B6B, "晚霞红"),
  autumnOrange(0xFFFF8A3D, "秋日橙"),
  lemonYellow(0xFFFFD23F, "柠檬黄"),
  oceanBlue(0xFF3D7BFF, "海洋蓝"),
  charmPurple(0xFF7B5CFF, "韵味紫"),
  sakuraPink(0xFFFF5DB1, "樱花粉"),
  deepSpaceBlack(0xFF141420, "深空黑");

  final int hex;
  final String label;

  const AppThemeColor(this.hex, this.label);

  /// 色板原色（选中指示器用）
  Color get color => Color(hex);
}

/// hex → HSL（h: 0~360，s: 0~100），与原型 hexToHsl 同算法
(int, int) hexToHsl(int hex) {
  final r = ((hex >> 16) & 0xFF) / 255;
  final g = ((hex >> 8) & 0xFF) / 255;
  final b = (hex & 0xFF) / 255;
  final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final l = (mx + mn) / 2;
  var h = 0.0, s = 0.0;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
  }
  return (h.round(), (s * 100).round());
}

Color _hsl(double h, int s, double l) =>
    HSLColor.fromAHSL(1, ((h % 360) + 360) % 360, s / 100, l).toColor();

/// 按主题色 + 明暗派生全部风格 A token
/// 亮度/不透明度数值均为原型 CSS 定稿值，不要随意调
AuroraTokens buildAuroraTokens(AppThemeColor seed, Brightness brightness) {
  final (h, sRaw) = hexToHsl(seed.hex);
  final h2 = h.toDouble();
  // 原型约束：饱和度下限 8，保证深空黑等低饱和色仍有可辨识的色相
  final s = sRaw > 8 ? sRaw : 8;
  final dark = brightness == Brightness.dark;

  return AuroraTokens(
    bg: dark ? const Color(0xFF08080E) : const Color(0xFFF4F3F7),
    bg2: dark ? const Color(0xFF0D0D16) : const Color(0xFFFFFFFF),
    fg: dark ? const Color(0xFFF5F5F8) : const Color(0xFF141420),
    fgDim: dark ? const Color(0xFF9C9CAB) : const Color(0xFF5C5C6B),
    fgMute: dark ? const Color(0xFF6B6B7A) : const Color(0xFF8A8A98),
    surface: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.055)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.72),
    surface2: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.09)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.90),
    hairline: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.10)
        : const Color(0xFF141420).withValues(alpha: 0.09),
    hairlineStrong: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.22)
        : const Color(0xFF141420).withValues(alpha: 0.20),
    primary: _hsl(h2, s, dark ? 0.66 : 0.48),
    primaryInk: dark ? const Color(0xFF0A0A10) : const Color(0xFFFFFFFF),
    glow: _hsl(h2, s, dark ? 0.60 : 0.62),
    shadow: dark
        ? const Color(0xFF000000).withValues(alpha: 0.55)
        : const Color(0xFF281E3C).withValues(alpha: 0.18),
    auroraOpacity: dark ? 0.55 : 0.40,
    coverBadgeBg: const Color(0xFF000000).withValues(alpha: 0.40),
    coverBadgeFg: const Color(0xFFFFFFFF),
    // Toast / 遮罩明暗同值（原型无 data-theme 覆写）
    toastBg: const Color(0xFF141418).withValues(alpha: 0.92),
    toastBorder: const Color(0xFFFFFFFF).withValues(alpha: 0.12),
    toastFg: const Color(0xFFFFFFFF),
    maskBg: const Color(0xFF000000).withValues(alpha: 0.50),
  );
}

/// 占位封面渐变（原型 grad()：140deg，hsl(h 72% 58%) → hsl(h+48 64% 42%)）
List<Color> coverGradientColors(int hue) => [
      _hsl(hue.toDouble(), 72, 0.58),
      _hsl((hue + 48).toDouble(), 64, 0.42),
    ];

/// 进度条填充渐变（原型 .bar .fill：90deg，primary → hsl(h+50 s 66%)，输入取当前主题色）
List<Color> progressGradientColors(Color primary) {
  final hsl = HSLColor.fromColor(primary);
  return [
    primary,
    hsl.withHue((hsl.hue + 50) % 360).withLightness(0.66).toColor(),
  ];
}
