import "package:flutter/material.dart";
import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../core/prefs/app_prefs.dart";

part "theme_mode_provider.g.dart";

const _themeModeKey = "theme_mode";

/// 明暗模式：真实持久化（默认亮色，所有者 2026-10-27 指定）
@riverpod
class AppThemeMode extends _$AppThemeMode {
  @override
  ThemeMode build() {
    return _from(appPrefs.getString(_themeModeKey));
  }

  void set(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    appPrefs.setString(_themeModeKey, _to(mode));
  }

  void toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  static ThemeMode _from(String? v) =>
      v == "dark" ? ThemeMode.dark : ThemeMode.light;

  static String _to(ThemeMode m) => m == ThemeMode.light ? "light" : "dark";
}
