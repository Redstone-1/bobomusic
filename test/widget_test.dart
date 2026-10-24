import "package:bobomusic/app/app.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

// S1.1 骨架冒烟：应用根可构建、Riverpod 状态链路可用
void main() {
  testWidgets("应用骨架冒烟：MaterialApp 正常构建", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text("S1.1 · 工程骨架已就绪"), findsOneWidget);
  });

  testWidgets("明暗切换：点按钮后 ThemeMode 翻转", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    // 默认暗色
    expect(find.text("切换到亮色"), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text("切换到暗色"), findsOneWidget);
  });
}
