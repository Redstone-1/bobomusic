import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../player/range_proxy_source.dart";

/// 应用版本（PackageInfo；测试/桌面异常时回退 pubspec 版本）
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber;
    return build.isEmpty ? info.version : "${info.version}+$build";
  } catch (_) {
    return "3.0.0";
  }
});

/// 音频缓存占用（字节；清理后 invalidate）
final audioCacheSizeProvider =
    FutureProvider<int>((ref) => RangeProxySource.cacheSize());

/// 字节数 → 人类可读（设置页缓存文案）
String formatBytes(int bytes) {
  if (bytes <= 0) return "0 B";
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return "${(bytes / gb).toStringAsFixed(1)} GB";
  if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(1)} MB";
  if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(1)} KB";
  return "$bytes B";
}
