import "dart:io";

import "package:device_info_plus/device_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

/// 下载到公共目录所需权限（与本地扫描的“读取音频”权限不同）：
/// Android 10+ 需要所有文件访问（写入 Download/啵啵音乐），9- 用存储权限
/// 非 Android 直接放行；永久拒绝时跳系统设置
Future<bool> requestDownloadPermission() async {
  if (!Platform.isAndroid) return true;
  final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  final permission =
      sdkInt >= 29 ? Permission.manageExternalStorage : Permission.storage;
  final status = await permission.request();
  if (status.isPermanentlyDenied) {
    await openAppSettings();
    return false;
  }
  return status.isGranted;
}
