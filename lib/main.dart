import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:just_audio_media_kit/just_audio_media_kit.dart";
import "package:path_provider/path_provider.dart";
import "package:permission_handler/permission_handler.dart";
import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

import "app/app.dart";
import "app/startup_failure_app.dart";
import "core/prefs/app_prefs.dart";
import "core/window/windows_window.dart";
import "data/db/app_database.dart";
import "data/db/desktop_database.dart";
import "data/db/windows_database_path.dart";
import "features/player/range_proxy_source.dart";
import "features/player/system_media_center.dart";

bool _databaseReady = false;

/// v3 入口：预取 SharedPreferences（主题同步初值）+ 桌面端 sqflite ffi
/// + 播放内核装配（桌面 media_kit 解码后端、音频缓存目录）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _initialize();
    runApp(const ProviderScope(child: App()));
  } catch (error) {
    print("应用启动失败：$error");
    if (_databaseReady) {
      await appDb.close();
      _databaseReady = false;
    }
    runApp(ProviderScope(
      child: StartupFailureApp(error: error, onRetry: () => main()),
    ));
  }
}

Future<void> _initialize() async {
  initDesktopDatabaseFactory();
  await initAppPrefs();
  if (Platform.isWindows) {
    if (windowsWindowController == null) {
      final controller = WindowsWindowController(appPrefs);
      await controller.initialize();
      windowsWindowController = controller;
    }
    final databasePath = await prepareWindowsDatabase(
      supportDirectory: await getApplicationSupportDirectory(),
      legacyPaths: windowsLegacyDatabasePaths(
        legacyDatabaseDirectory: await getDatabasesPath(),
        workingDirectory: Directory.current.path,
        executableDirectory: p.dirname(Platform.resolvedExecutable),
      ),
      factory: databaseFactory,
    );
    await initAppDatabase(path: databasePath);
  } else {
    await initAppDatabase();
  }
  _databaseReady = true;
  // 桌面（Windows/Linux）解码走 media_kit；Android 用平台默认解码器
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }
  // 音频边下边播缓存目录（key=origin-id 哈希，LRU 治理见 RangeProxySource）
  final cacheRoot = await getApplicationCacheDirectory();
  RangeProxySource.cacheDir = Directory("${cacheRoot.path}/bobomusic_audio")
    ..createSync(recursive: true);
  // 共用命令与快照协议；Windows 原生端负责 SMTC，不创建第二个播放器。
  if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
    await initSystemMediaCenter();
    if (Platform.isAndroid) {
      // Android 13+ 通知权限：没有它媒体通知不显示（iOS 正在播放卡不需要权限）
      try {
        await Permission.notification.request();
      } catch (_) {
        // 权限插件失败不影响播放
      }
    }
  }
}
