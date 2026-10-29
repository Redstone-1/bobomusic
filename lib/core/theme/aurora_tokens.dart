import "package:flutter/material.dart";

/// 风格 A · 沉浸极光玻璃 的全部视觉 token（ThemeExtension 承载）
/// 数值来源：prototype/style-a-aurora/index.html 的 CSS 变量定稿
@immutable
class AuroraTokens extends ThemeExtension<AuroraTokens> {
  // ---- 颜色 ----
  /// 页面底色（--bg）
  final Color bg;

  /// 面板底色（--bg2，底部面板/播放卡片用）
  final Color bg2;

  /// 主文字（--fg）
  final Color fg;

  /// 次级文字（--fg-dim）
  final Color fgDim;

  /// 弱化文字（--fg-mute）
  final Color fgMute;

  /// 玻璃表面一层（--surface）
  final Color surface;

  /// 玻璃表面二层（--surface-2）
  final Color surface2;

  /// 发丝描边（--line，1px）
  final Color hairline;

  /// 强描边（--line-strong）
  final Color hairlineStrong;

  /// 主题色（--primary）
  final Color primary;

  /// 主题色上的文字（--primary-ink）
  final Color primaryInk;

  /// 主题色辉光（--glow，阴影/发光用）
  final Color glow;

  /// 投影色（--shadow）
  final Color shadow;

  /// 极光光斑不透明度（暗 .55 / 亮 .40）
  final double auroraOpacity;

  /// 封面角标底色（原型 .cover .badge：rgba(0,0,0,.4)）
  final Color coverBadgeBg;

  /// 封面角标文字
  final Color coverBadgeFg;

  /// Toast 底色（原型 .toast：rgba(20,20,24,.92)，明暗同值——深色胶囊在两主题下都可读）
  final Color toastBg;

  /// Toast 描边（原型 rgba(255,255,255,.12)，明暗同值）
  final Color toastBorder;

  /// Toast 文字（明暗同值）
  final Color toastFg;

  /// 弹层遮罩（原型 .sheet .mask：rgba(0,0,0,.5)，明暗同值）
  final Color maskBg;

  /// 扫描舱固定黑灰底（明暗同值，不随主题变化，突出黑客感）
  final Color scanSurface;

  // ---- 圆角分级（原型 12/14/18~20/26 收敛） ----
  /// 小件：列表封面、小图（12）
  final double radiusSm;

  /// 行内交互：列表行、歌单行（14）
  final double radiusMd;

  /// 卡片：玻璃卡、网格封面（18）
  final double radiusLg;

  /// 大容器：底部面板（26）
  final double radiusXl;

  // ---- 动效 ----
  /// 标准动效曲线 cubic-bezier(.2,.8,.2,1)
  final Curve motionCurve;

  /// 强调动效曲线 cubic-bezier(.2,.9,.2,1)（面板滑入）
  final Curve motionCurveEmphasized;

  /// 按压/悬停（200ms）
  final Duration motionFast;

  /// 位移/展开（350ms）
  final Duration motionNormal;

  /// 页面/面板进出场（450~500ms）
  final Duration motionSlow;

  // ---- 玻璃参数 ----
  /// 玻璃模糊 sigma（原型迷你条 blur(20px)）
  final double glassBlurSigma;

  /// 玻璃饱和度增益（原型 saturate(160%)）
  final double glassSaturation;

  const AuroraTokens({
    required this.bg,
    required this.bg2,
    required this.fg,
    required this.fgDim,
    required this.fgMute,
    required this.surface,
    required this.surface2,
    required this.hairline,
    required this.hairlineStrong,
    required this.primary,
    required this.primaryInk,
    required this.glow,
    required this.shadow,
    required this.auroraOpacity,
    required this.coverBadgeBg,
    required this.coverBadgeFg,
    required this.toastBg,
    required this.toastBorder,
    required this.toastFg,
    required this.maskBg,
    required this.scanSurface,
    this.radiusSm = 12,
    this.radiusMd = 14,
    this.radiusLg = 18,
    this.radiusXl = 26,
    this.motionCurve = const Cubic(0.2, 0.8, 0.2, 1),
    this.motionCurveEmphasized = const Cubic(0.2, 0.9, 0.2, 1),
    this.motionFast = const Duration(milliseconds: 200),
    this.motionNormal = const Duration(milliseconds: 350),
    this.motionSlow = const Duration(milliseconds: 500),
    this.glassBlurSigma = 20,
    this.glassSaturation = 1.6,
  });

  /// 取当前上下文的 token（颜色一律从这里走，禁止硬编码）
  static AuroraTokens of(BuildContext context) =>
      Theme.of(context).extension<AuroraTokens>()!;

  @override
  AuroraTokens copyWith({
    Color? bg,
    Color? bg2,
    Color? fg,
    Color? fgDim,
    Color? fgMute,
    Color? surface,
    Color? surface2,
    Color? hairline,
    Color? hairlineStrong,
    Color? primary,
    Color? primaryInk,
    Color? glow,
    Color? shadow,
    double? auroraOpacity,
    Color? coverBadgeBg,
    Color? coverBadgeFg,
    Color? toastBg,
    Color? toastBorder,
    Color? toastFg,
    Color? maskBg,
    Color? scanSurface,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    Curve? motionCurve,
    Curve? motionCurveEmphasized,
    Duration? motionFast,
    Duration? motionNormal,
    Duration? motionSlow,
    double? glassBlurSigma,
    double? glassSaturation,
  }) {
    return AuroraTokens(
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      fg: fg ?? this.fg,
      fgDim: fgDim ?? this.fgDim,
      fgMute: fgMute ?? this.fgMute,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      primary: primary ?? this.primary,
      primaryInk: primaryInk ?? this.primaryInk,
      glow: glow ?? this.glow,
      shadow: shadow ?? this.shadow,
      auroraOpacity: auroraOpacity ?? this.auroraOpacity,
      coverBadgeBg: coverBadgeBg ?? this.coverBadgeBg,
      coverBadgeFg: coverBadgeFg ?? this.coverBadgeFg,
      toastBg: toastBg ?? this.toastBg,
      toastBorder: toastBorder ?? this.toastBorder,
      toastFg: toastFg ?? this.toastFg,
      maskBg: maskBg ?? this.maskBg,
      scanSurface: scanSurface ?? this.scanSurface,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      motionCurve: motionCurve ?? this.motionCurve,
      motionCurveEmphasized:
          motionCurveEmphasized ?? this.motionCurveEmphasized,
      motionFast: motionFast ?? this.motionFast,
      motionNormal: motionNormal ?? this.motionNormal,
      motionSlow: motionSlow ?? this.motionSlow,
      glassBlurSigma: glassBlurSigma ?? this.glassBlurSigma,
      glassSaturation: glassSaturation ?? this.glassSaturation,
    );
  }

  @override
  AuroraTokens lerp(AuroraTokens? other, double t) {
    if (other == null) return this;
    // 颜色参与插值（明暗/主题色切换的渐变过渡）；几何与动效参数直接沿用当前值
    return AuroraTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fgDim: Color.lerp(fgDim, other.fgDim, t)!,
      fgMute: Color.lerp(fgMute, other.fgMute, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryInk: Color.lerp(primaryInk, other.primaryInk, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      auroraOpacity: _lerpDouble(auroraOpacity, other.auroraOpacity, t),
      coverBadgeBg: Color.lerp(coverBadgeBg, other.coverBadgeBg, t)!,
      coverBadgeFg: Color.lerp(coverBadgeFg, other.coverBadgeFg, t)!,
      toastBg: Color.lerp(toastBg, other.toastBg, t)!,
      toastBorder: Color.lerp(toastBorder, other.toastBorder, t)!,
      toastFg: Color.lerp(toastFg, other.toastFg, t)!,
      maskBg: Color.lerp(maskBg, other.maskBg, t)!,
      scanSurface: Color.lerp(scanSurface, other.scanSurface, t)!,
      radiusSm: _lerpDouble(radiusSm, other.radiusSm, t),
      radiusMd: _lerpDouble(radiusMd, other.radiusMd, t),
      radiusLg: _lerpDouble(radiusLg, other.radiusLg, t),
      radiusXl: _lerpDouble(radiusXl, other.radiusXl, t),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
