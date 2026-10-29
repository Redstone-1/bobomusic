import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/theme_mode_provider.dart";
import "package:bobomusic/core/theme/theme_providers.dart";
import "package:bobomusic/core/widgets/page_header.dart";
import "package:bobomusic/core/widgets/theme_swatch.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/settings/settings_page.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

Future<void> _prepare(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // 复用测试偏好和播放依赖，单独装载设置页以检查窄屏布局。
  await buildTestApp(prefs: prefs);
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: ref.watch(appLightThemeProvider),
          darkTheme: ref.watch(appDarkThemeProvider),
          themeMode: ref.watch(appThemeModeProvider),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  playbackDepsTestOverride = null;
  await appDb.close();
}

Finder _swatch(AppThemeColor color) => find.byWidgetPredicate(
      (widget) => widget is ThemeSwatch && widget.color == color,
    );

Color _swatchColor(WidgetTester tester, AppThemeColor color) {
  final container = tester.widget<Container>(
    find.descendant(of: _swatch(color), matching: find.byType(Container)),
  );
  return (container.decoration! as BoxDecoration).color!;
}

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsPage))).colorScheme;

Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets("主题色无副标题，标题右侧月亮与太阳切换明暗并保留配色", (tester) async {
    await _prepare(tester, prefs: {"theme_color": "sunsetRed"});
    expect(find.text("主题模式"), findsNothing);
    expect(find.text("主题色驱动 · 明暗自动生成"), findsNothing);
    expect(find.text("浅色"), findsNothing);
    expect(find.text("深色"), findsNothing);
    expect(find.text("主题色"), findsOneWidget);
    expect(find.byType(ThemeSwatch), findsNWidgets(8));
    expect(
      find.descendant(
        of: find.byType(PageHeader),
        matching: find.byTooltip("切换为深色"),
      ),
      findsOneWidget,
    );
    final moon = find.byIcon(Icons.dark_mode_outlined);
    expect(moon, findsOneWidget);
    expect(tester.getCenter(moon).dx, greaterThan(300));
    final before = _scheme(tester).primary;

    await _toggle(tester, "切换为深色");
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    expect(_scheme(tester).primary, isNot(before));
    expect(appPrefs.getString("theme_mode"), "dark");
    expect(appPrefs.getString("theme_color"), "sunsetRed");

    await _toggle(tester, "切换为浅色");
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(_scheme(tester).primary, before);
    expect(appPrefs.getString("theme_mode"), "light");
    expect(appPrefs.getString("theme_color"), "sunsetRed");
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets("中性色预览跟随实际明暗颜色，紫色应用色与原色预览一致", (tester) async {
    await _prepare(tester);
    final black = _swatch(AppThemeColor.deepSpaceBlack);
    await tester.tap(black);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_scheme(tester).primary, const Color(0xFF7A7A7A));
    expect(_swatchColor(tester, AppThemeColor.deepSpaceBlack),
        _scheme(tester).primary);
    expect(_swatchColor(tester, AppThemeColor.charmPurple),
        const Color(0xFF7B5CFF));
    final lightPreview = _swatchColor(tester, AppThemeColor.deepSpaceBlack);

    await _toggle(tester, "切换为深色");
    expect(_scheme(tester).primary, const Color(0xFFA8A8A8));
    expect(_swatchColor(tester, AppThemeColor.deepSpaceBlack),
        _scheme(tester).primary);
    expect(_swatchColor(tester, AppThemeColor.deepSpaceBlack),
        isNot(lightPreview));
    final check = tester.widget<Icon>(
      find.descendant(of: black, matching: find.byIcon(Icons.check)),
    );
    expect(check.color, _scheme(tester).onPrimary);

    await tester.tap(_swatch(AppThemeColor.charmPurple));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_scheme(tester).primary, const Color(0xFF7B5CFF));
    expect(_scheme(tester).primary,
        _swatchColor(tester, AppThemeColor.charmPurple));
    expect(appPrefs.getString("theme_color"), "charmPurple");

    await _toggle(tester, "切换为浅色");
    expect(_scheme(tester).primary, const Color(0xFF7B5CFF));
    expect(_scheme(tester).primary,
        _swatchColor(tester, AppThemeColor.charmPurple));
    expect(appPrefs.getString("theme_color"), "charmPurple");
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets("冷启动读回深色和紫色偏好，右上角提供太阳切换入口", (tester) async {
    await _prepare(tester, prefs: {
      "theme_color": "charmPurple",
      "theme_mode": "dark",
    });
    expect(find.byTooltip("切换为浅色"), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(_scheme(tester).brightness, Brightness.dark);
    expect(_scheme(tester).primary, const Color(0xFF7B5CFF));
    expect(
        tester.widget<ThemeSwatch>(_swatch(AppThemeColor.charmPurple)).selected,
        isTrue);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets("320 窄屏放大字号时主题入口和色块无溢出", (tester) async {
    await _prepare(tester, width: 320, scale: 1.3);
    expect(find.byTooltip("切换为深色"), findsOneWidget);
    expect(find.byType(ThemeSwatch), findsNWidgets(8));
    for (final color in AppThemeColor.values) {
      final rect = tester.getRect(_swatch(color));
      expect(rect.left, greaterThanOrEqualTo(20));
      expect(rect.right, lessThanOrEqualTo(300));
    }
    await _toggle(tester, "切换为深色");
    expect(find.byTooltip("切换为浅色"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });
}
