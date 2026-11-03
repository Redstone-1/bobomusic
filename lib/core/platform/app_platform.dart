import "dart:io";

import "package:flutter_riverpod/flutter_riverpod.dart";

enum AppPlatform { android, windows, macos, linux, other }

/// 平台决定使用哪套应用壳，窗口宽度只决定桌面壳内部布局；测试可显式覆盖。
final appPlatformProvider = Provider<AppPlatform>((ref) {
  if (Platform.isWindows) return AppPlatform.windows;
  if (Platform.isAndroid) return AppPlatform.android;
  if (Platform.isMacOS) return AppPlatform.macos;
  if (Platform.isLinux) return AppPlatform.linux;
  return AppPlatform.other;
});

extension AppPlatformCapabilities on AppPlatform {
  bool get usesDesktopLayout => this == AppPlatform.windows;
}
