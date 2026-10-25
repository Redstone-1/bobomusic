import "dart:io";

import "package:sqflite_common_ffi/sqflite_ffi.dart";

/// 桌面端（Windows/Linux）sqflite ffi 引导；Android 走平台内置实现
void initDesktopDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
