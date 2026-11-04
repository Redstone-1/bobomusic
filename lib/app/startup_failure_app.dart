import "package:flutter/material.dart";

import "../core/theme/app_palette.dart";
import "../core/theme/app_theme.dart";
import "../core/theme/aurora_tokens.dart";

/// 初始化失败时仍提供可见错误出口；不能把迁移失败掩盖成一个空白音乐库。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp(
      {super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppThemeColor.autumnOrange, Brightness.dark),
        home: Builder(builder: (context) {
          final t = AuroraTokens.of(context);
          return Scaffold(
              body: Center(
                  child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, color: t.primary, size: 42),
                  const SizedBox(height: 18),
                  const Text("啵啵音乐启动失败", style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 18),
                  SelectableText("$error", style: TextStyle(color: t.fgDim)),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text("重试")),
                ])),
          )));
        }),
      );
}
