import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/theme/theme_mode_provider.dart";

/// 应用根 Widget：装配主题与全局壳
/// S1.2 起替换为风格 A token 主题（ThemeExtension）；S1.4 起由三 Tab 导航壳接管 home
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      themeMode: themeMode,
      home: const _SkeletonPlaceholder(),
    );
  }
}

/// S1.1 占位页：验证 Riverpod 状态链路（点按钮切明暗），S1.4 整体移除
class _SkeletonPlaceholder extends ConsumerWidget {
  const _SkeletonPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("S1.1 · 工程骨架已就绪"),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref.read(appThemeModeProvider.notifier).toggle(),
              icon: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
              ),
              label: Text(themeMode == ThemeMode.dark ? "切换到亮色" : "切换到暗色"),
            ),
          ],
        ),
      ),
    );
  }
}
