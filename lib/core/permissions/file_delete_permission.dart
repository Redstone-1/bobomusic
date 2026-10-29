import "dart:io";

import "package:device_info_plus/device_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

/// 删除公共目录源文件所需权限（与本地扫描的“读取音频”不同）：
/// Android 11+ 分区存储下 READ_MEDIA_AUDIO 只能读，删除文件需要所有文件访问；
/// Android 10 及以下用存储权限。非 Android（桌面联调/测试）直接放行；
/// 永久拒绝时跳系统设置，提示由 UI 层负责
Future<bool> requestFileDeletePermission() async {
  if (!Platform.isAndroid) return true;
  final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  final permission =
      sdkInt >= 30 ? Permission.manageExternalStorage : Permission.storage;
  if (await permission.isGranted) return true;
  final status = await permission.request();
  // 所有文件访问会跳系统设置授权，返回后以实际状态为准
  if (status.isGranted || await permission.isGranted) return true;
  if (status.isPermanentlyDenied) await openAppSettings();
  return false;
}
