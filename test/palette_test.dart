import "package:bobomusic/core/theme/app_palette.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

// 8 色派生与 token 的纯逻辑校验（S1.2）
void main() {
  group("hexToHsl", () {
    test("晚霞红解析出红色相与高饱和", () {
      final (h, s) = hexToHsl(0xFFFF3B6B);
      expect(h, inInclusiveRange(338, 348));
      expect(s, greaterThan(80));
    });

    test("深空黑是低饱和色", () {
      // RGB(20,20,32) 的 HSL 饱和度 = 12/52 ≈ 23%，8 色中最低
      final (_, s) = hexToHsl(0xFF141420);
      expect(s, inInclusiveRange(20, 26));
    });
  });

  group("buildAuroraTokens", () {
    test("深空黑派生保留源色低饱和度", () {
      final t = buildAuroraTokens(AppThemeColor.deepSpaceBlack, Brightness.dark);
      expect(
        HSLColor.fromColor(t.primary).saturation * 100,
        closeTo(23, 0.1),
      );
    });

    test("明暗两套表面与主题色亮度不同", () {
      for (final seed in AppThemeColor.values) {
        final dark = buildAuroraTokens(seed, Brightness.dark);
        final light = buildAuroraTokens(seed, Brightness.light);
        expect(dark.primary, isNot(light.primary));
        expect(dark.surface.a, lessThan(light.surface.a));
        expect(dark.bg, isNot(light.bg));
      }
    });

    test("全 8 色 × 明暗构建无异常且 lerp 端点正确", () {
      for (final seed in AppThemeColor.values) {
        final dark = buildAuroraTokens(seed, Brightness.dark);
        final light = buildAuroraTokens(seed, Brightness.light);
        expect(dark.lerp(light, 0).primary, dark.primary);
        expect(dark.lerp(light, 1).primary, light.primary);
      }
    });
  });

  test("占位封面渐变输出两色", () {
    final colors = coverGradientColors(212);
    expect(colors, hasLength(2));
    expect(colors[0], isNot(colors[1]));
  });
}
