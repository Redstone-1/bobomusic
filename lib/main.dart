import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "app/app.dart";
import "core/prefs/app_prefs.dart";
import "data/db/app_database.dart";
import "data/db/desktop_database.dart";

/// v3 入口：预取 SharedPreferences（主题同步初值）+ 桌面端 sqflite ffi
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDesktopDatabaseFactory();
  await initAppPrefs();
  await initAppDatabase();
  runApp(const ProviderScope(child: App()));
}
