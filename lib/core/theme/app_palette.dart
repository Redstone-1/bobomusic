import "dart:ui" show Brightness;

import "package:flutter/painting.dart";

import "aurora_tokens.dart";

/// 10 种主题色原色；实际强调色统一从 buildAuroraTokens 读取。
/// 橙色置首 = 默认主题色（所有者 2026-11-04 修订）
enum AppThemeColor {
  autumnOrange(0xFFFF8A3D, "秋日橙"),
  natureGreen(0xFF2EC4B6, "青绿色"),
  deepSpaceBlack(0xFF141414, "深空黑"),
  sunsetRed(0xFFFF3B6B, "晚霞红"),
  lemonYellow(0xFFFFD23F, "柠檬黄"),
  leafGreen(0xFF71C75B, "草木绿"),
  skyCyan(0xFF38BDF8, "晴空青"),
  oceanBlue(0xFF3D7BFF, "海洋蓝"),
  charmPurple(0xFF7B5CFF, "韵味紫"),
  sakuraPink(0xFFFF5DB1, "樱花粉");

  final int hex;
  final String label;

  const AppThemeColor(this.hex, this.label);

  /// 色板原色；中性色预览使用当前明暗下的实际强调色。
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

/// 按主题色 + 明暗派生极光主题 token；韵味紫强调色保持色板原色。
AuroraTokens buildAuroraTokens(AppThemeColor seed, Brightness brightness) {
  final (h, sRaw) = hexToHsl(seed.hex);
  final h2 = h.toDouble();
  // 饱和度原样使用：纯中性色（s=0，如深空黑）保持中性——
  // 曾用"下限 8% 托底"，纯黑 h=0（红色相）被托成 8% 红 = 棕褐（2026-10-27 修正）
  final s = sRaw;
  final dark = brightness == Brightness.dark;

  return AuroraTokens(
    bg: dark ? const Color(0xFF08080E) : const Color(0xFFF4F3F7),
    bg2: dark ? const Color(0xFF0D0D16) : const Color(0xFFFFFFFF),
    fg: dark ? const Color(0xFFF5F5F8) : const Color(0xFF141420),
    fgDim: dark ? const Color(0xFF9C9CAB) : const Color(0xFF5C5C6B),
    fgMute: dark ? const Color(0xFF6B6B7A) : const Color(0xFF8A8A98),
    // 亮色玻璃拟态：表面需保留足够透明度让极光背景透出（对齐暗色的通透思路），
    // 白色 72%/90% 近乎实心，模糊层被盖死；45%/72% 为第二轮（所有者反馈首版 55%/80% 仍不够透）。
    surface: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.055)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.45),
    surface2: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.09)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.72),
    // 弹层瓦片填充：亮色用实感浅灰（半透明白叠纯白面板 bg2 会隐形），
    // 暗色与 surface 同值不变（所有者 2026-11-07 钦定新增 token 方案）
    tileBg: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.055)
        : const Color(0xFF141420).withValues(alpha: 0.05),
    hairline: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.10)
        : const Color(0xFF141420).withValues(alpha: 0.09),
    hairlineStrong: dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.22)
        : const Color(0xFF141420).withValues(alpha: 0.20),
    // 紫色以色板原色为准，避免明暗派生改变用户选中的紫色。
    primary: seed == AppThemeColor.charmPurple
        ? seed.color
        : _hsl(h2, s, dark ? 0.66 : 0.48),
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
    // 扫描舱固定黑灰：不随明暗/主题变化，保证黑客感
    scanSurface: const Color(0xFF0A0D10),
  );
}

/// 占位封面渐变（所有者 2026-10-27 定稿：低饱和低亮度双色微差，柔和耐看不抢内容；
/// 原型 72%/64% 饱和度版本过艳已废弃）
List<Color> coverGradientColors(int hue) => [
      _hsl(hue.toDouble(), 38, 0.52),
      _hsl((hue + 40).toDouble(), 30, 0.36),
    ];

/// 进度条填充渐变（原型 .bar .fill：90deg，primary → hsl(h+50 s 66%)，输入取当前主题色）
List<Color> progressGradientColors(Color primary) {
  final hsl = HSLColor.fromColor(primary);
  return [
    primary,
    hsl.withHue((hsl.hue + 50) % 360).withLightness(0.66).toColor(),
  ];
}
