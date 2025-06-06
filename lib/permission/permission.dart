import "dart:async";
import "package:bot_toast/bot_toast.dart";
import "package:device_info_plus/device_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

class Permissions {
  static Future<bool> requestAudioOrStoragePermission() async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;

    if (deviceInfo.version.sdkInt >= 33) { // Android 13+
      final permission = await Permission.audio.request();
      if (permission.isPermanentlyDenied) {
        BotToast.showText(text: "请打开音频读取权限");
        Timer(const Duration(seconds: 1), () => openAppSettings());
        return false;
      }
      return permission.isGranted;
    } else if (deviceInfo.version.sdkInt >= 29) { // Android 10+
      final permission = await Permission.manageExternalStorage.request();
      if (permission.isPermanentlyDenied) {
        BotToast.showText(text: "请打开存储权限");
        Timer(const Duration(seconds: 1), () => openAppSettings());
        return false;
      }
      return permission.isGranted;
    } else { // Android 9及以下
      return await Permission.storage.request().isGranted;
    }
  }

  // 新增：通知权限请求
  static Future<bool> requestNotificationPermission() async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;

    // 仅Android 13+需要请求通知权限
    if (deviceInfo.version.sdkInt >= 33) {
      final status = await Permission.notification.request();

      if (status.isDenied || status.isPermanentlyDenied) {
        BotToast.showText(text: "请打开通知权限");
        Timer(const Duration(seconds: 1), () => openAppSettings());
        return false;
      }
    }

    return true; // Android 13以下默认有权限
  }
}