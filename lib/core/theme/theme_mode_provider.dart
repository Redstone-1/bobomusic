import "package:flutter/material.dart";
import "package:riverpod_annotation/riverpod_annotation.dart";

part "theme_mode_provider.g.dart";

/// 明暗模式
/// S1.1 为 codegen 冒烟骨架（默认暗色，贴合风格 A 的沉浸式基调）；
/// S3.1 接入 SharedPreferences 真实持久化
@riverpod
class AppThemeMode extends _$AppThemeMode {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  /// 直接指定模式（设置页分段控件用）
  void set(ThemeMode mode) {
    if (state != mode) state = mode;
  }
}
