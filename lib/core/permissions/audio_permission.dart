import "dart:io";

import "package:device_info_plus/device_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

/// 本地扫描权限请求（沿 2.7.0 三分支策略）：
/// Android 13+ 音频权限 / 10~12 所有文件访问 / 9 及以下存储权限
/// 非 Android（桌面联调/测试）直接放行；永久拒绝时跳系统设置，提示由 UI 层负责
Future<bool> requestAudioPermission() async {
  if (!Platform.isAndroid) return true;
  final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  final Permission permission;
  if (sdkInt >= 33) {
    permission = Permission.audio;
  } else if (sdkInt >= 29) {
    permission = Permission.manageExternalStorage;
  } else {
    permission = Permission.storage;
  }
  final status = await permission.request();
  if (status.isPermanentlyDenied) {
    await openAppSettings();
    return false;
  }
  return status.isGranted;
}
