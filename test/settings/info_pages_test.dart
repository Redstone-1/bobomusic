import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/back_link.dart";
import "package:bobomusic/features/settings/info_pages.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Widget _wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.dark),
      home: child,
    );

void main() {
  testWidgets("声明页：分节卡片与关键说明可见", (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const DeclarationPage()));
    await tester.pump();

    expect(find.text("声明与限制"), findsOneWidget);
    expect(find.text("数据与隐私"), findsOneWidget);
    expect(find.text("内容版权"), findsOneWidget);
    expect(find.text("下载内容"), findsOneWidget);
    expect(find.byType(BackLink), findsOneWidget);
  });

  testWidgets("鸣谢页：特别感谢与开源组件卡片可见", (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ThanksPage()));
    await tester.pump();

    expect(find.text("鸣谢"), findsOneWidget);
    expect(find.text("特别感谢"), findsOneWidget);
    // FlutterUnit 已从鸣谢移除（2026-11-07）：特别感谢区只剩 bbmusic
    expect(find.text("bbmusic"), findsOneWidget);
    expect(find.text("FlutterUnit"), findsNothing);
    expect(find.text("开源组件"), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsWidgets);
  });
}
