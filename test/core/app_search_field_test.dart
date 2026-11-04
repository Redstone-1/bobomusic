import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/app_search_field.dart";
import "package:bobomusic/core/widgets/glass_card.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets("$brightness 搜索框聚焦后仍使用玻璃外框，清除文字不改变高度", (tester) async {
      final controller = TextEditingController();
      final changes = <String>[];
      final theme = buildAppTheme(AppThemeColor.natureGreen, brightness);
      await tester.pumpWidget(MaterialApp(
        // 即使宿主设置了默认填充和下划线，公共搜索框也要保持项目的视觉基线。
        theme: theme.copyWith(
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          border: const UnderlineInputBorder(),
          enabledBorder: const UnderlineInputBorder(),
          focusedBorder: const UnderlineInputBorder(),
        )),
        home: Scaffold(
            body: Center(
                child: SizedBox(
          width: 320,
          child: AppSearchField(
              controller: controller, hintText: "搜索列表", onChanged: changes.add),
        ))),
      ));
      final height = tester.getSize(find.byType(AppSearchField)).height;
      expect(tester.widget<GlassCard>(find.byType(GlassCard)).frosted, isTrue);
      expect(find.byTooltip("清除搜索"), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), "测试");
      await tester.pump();
      final input = tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(input.isFocused, isTrue);
      expect(input.decoration.border, InputBorder.none);
      expect(input.decoration.enabledBorder, InputBorder.none);
      expect(input.decoration.focusedBorder, InputBorder.none);
      expect(input.decoration.filled, isFalse);
      expect(tester.getSize(find.byType(AppSearchField)).height, height);
      await tester.tap(find.byTooltip("清除搜索"));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes, ["测试", ""]);
      expect(find.byTooltip("清除搜索"), findsNothing);
      expect(tester.getSize(find.byType(AppSearchField)).height, height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
