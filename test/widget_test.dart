import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

// S1.2 设计系统冒烟：验证页可构建、8 色切换驱动 ThemeData
// 注意：页面含极光/均衡器常驻动画，只 pump 固定帧，禁止 pumpAndSettle
void main() {
  testWidgets("设计系统验证页：组件陈列可构建", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    expect(find.text("S1.3 · 全局组件"), findsOneWidget);
    expect(find.byKey(const ValueKey("seed_oceanBlue")), findsOneWidget);
  });

  testWidgets("点击主题色点 → ThemeData 跟随切换", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    await tester.tap(find.byKey(const ValueKey("seed_oceanBlue")));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final expected = buildAuroraTokens(
      AppThemeColor.oceanBlue,
      Brightness.dark,
    );
    expect(app.darkTheme?.colorScheme.primary, expected.primary);
  });
}
