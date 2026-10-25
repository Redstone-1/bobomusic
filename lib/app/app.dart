import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "design_system_demo.dart";
import "../core/theme/theme_mode_provider.dart";
import "../core/theme/theme_providers.dart";

/// 应用根 Widget：装配主题与全局壳
/// S1.4 起由三 Tab 导航壳接管 home；当前 home 为设计系统验证页
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final light = ref.watch(appLightThemeProvider);
    final dark = ref.watch(appDarkThemeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      home: const DesignSystemDemo(),
      // BotToast 全局挂载（Toast / 加载态入口，S1.3）
      navigatorObservers: [BotToastNavigatorObserver()],
      builder: BotToastInit(),
    );
  }
}
