import "package:flutter/material.dart";
import "package:riverpod_annotation/riverpod_annotation.dart";

import "app_palette.dart";
import "app_theme.dart";

part "theme_providers.g.dart";

/// 当前主题色（默认晚霞红，与原型启动色一致；S3.1 接持久化）
@riverpod
class AppThemeSeed extends _$AppThemeSeed {
  @override
  AppThemeColor build() => AppThemeColor.sunsetRed;

  void select(AppThemeColor color) => state = color;
}

/// 亮色 ThemeData
@riverpod
ThemeData appLightTheme(Ref ref) =>
    buildAppTheme(ref.watch(appThemeSeedProvider), Brightness.light);

/// 暗色 ThemeData
@riverpod
ThemeData appDarkTheme(Ref ref) =>
    buildAppTheme(ref.watch(appThemeSeedProvider), Brightness.dark);
