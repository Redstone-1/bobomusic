import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:just_audio_media_kit/just_audio_media_kit.dart";
import "package:path_provider/path_provider.dart";
import "package:permission_handler/permission_handler.dart";

import "app/app.dart";
import "core/prefs/app_prefs.dart";
import "data/db/app_database.dart";
import "data/db/desktop_database.dart";
import "features/player/range_proxy_source.dart";
import "features/player/system_media_center.dart";

/// v3 入口：预取 SharedPreferences（主题同步初值）+ 桌面端 sqflite ffi
/// + 播放内核装配（桌面 media_kit 解码后端、音频缓存目录）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDesktopDatabaseFactory();
  await initAppPrefs();
  await initAppDatabase();
  // 桌面（Windows/Linux）解码走 media_kit；Android 用平台默认解码器
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }
  // 音频边下边播缓存目录（key=origin-id 哈希，LRU 治理见 RangeProxySource）
  final cacheRoot = await getApplicationCacheDirectory();
  RangeProxySource.cacheDir = Directory("${cacheRoot.path}/bobomusic_audio")
    ..createSync(recursive: true);
  // Android 自研媒体中心：通知栏/锁屏/耳机键/原子岛（其他平台跳过；失败不阻塞启动）
  if (Platform.isAndroid) {
    await initSystemMediaCenter();
    // Android 13+ 通知权限：没有它媒体通知不显示
    try {
      await Permission.notification.request();
    } catch (_) {
      // 权限插件失败不影响播放
    }
  }
  runApp(const ProviderScope(child: App()));
}
