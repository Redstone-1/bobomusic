import "package:flutter/material.dart";
import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../core/prefs/app_prefs.dart";
import "app_palette.dart";
import "app_theme.dart";

part "theme_providers.g.dart";

const _themeColorKey = "theme_color";

/// 当前主题色（默认自然绿——所有者指定第四色；S3.1 起真实持久化）
@riverpod
class AppThemeSeed extends _$AppThemeSeed {
  @override
  AppThemeColor build() {
    final name = appPrefs.getString(_themeColorKey);
    try {
      return AppThemeColor.values.byName(name!);
    } catch (_) {
      return AppThemeColor.natureGreen;
    }
  }

  void select(AppThemeColor color) {
    if (state == color) return;
    state = color;
    appPrefs.setString(_themeColorKey, color.name);
  }
}

/// 亮色 ThemeData
@riverpod
ThemeData appLightTheme(Ref ref) =>
    buildAppTheme(ref.watch(appThemeSeedProvider), Brightness.light);

/// 暗色 ThemeData
@riverpod
ThemeData appDarkTheme(Ref ref) =>
    buildAppTheme(ref.watch(appThemeSeedProvider), Brightness.dark);
