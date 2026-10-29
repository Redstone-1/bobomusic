import "package:bobomusic/core/theme/app_palette.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

// 10 色派生与 token 的纯逻辑校验（S1.2）
void main() {
  group("hexToHsl", () {
    test("晚霞红解析出红色相与高饱和", () {
      final (h, s) = hexToHsl(0xFFFF3B6B);
      expect(h, inInclusiveRange(338, 348));
      expect(s, greaterThan(80));
    });

    test("深空黑是纯中性色", () {
      // 2026-10-27 修正：0xFF141420 蓝偏（R20 B32）→ 0xFF141414 三通道相等，饱和度 0
      final (_, s) = hexToHsl(AppThemeColor.deepSpaceBlack.hex);
      expect(s, 0);
    });
  });

  group("buildAuroraTokens", () {
    test("深空黑派生保持纯中性（无色相偏移）", () {
      final t =
          buildAuroraTokens(AppThemeColor.deepSpaceBlack, Brightness.dark);
      expect(
        HSLColor.fromColor(t.primary).saturation * 100,
        0,
      );
    });

    test("韵味紫在明暗主题中均使用色板原色", () {
      for (final brightness in Brightness.values) {
        final t = buildAuroraTokens(AppThemeColor.charmPurple, brightness);
        expect(t.primary, const Color(0xFF7B5CFF));
      }
    });

    test("明暗表面不同，其余主题色仍按亮度派生", () {
      for (final seed in AppThemeColor.values) {
        final dark = buildAuroraTokens(seed, Brightness.dark);
        final light = buildAuroraTokens(seed, Brightness.light);
        if (seed != AppThemeColor.charmPurple) {
          expect(dark.primary, isNot(light.primary));
        }
        expect(dark.primaryInk, isNot(light.primaryInk));
        expect(dark.surface.a, lessThan(light.surface.a));
        expect(dark.bg, isNot(light.bg));
      }
    });

    test("全 10 色 × 明暗构建无异常且 lerp 端点正确", () {
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
