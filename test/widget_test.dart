import "dart:ui" show Size;

import "package:bobomusic/app/app.dart";
import "package:bobomusic/features/home/home_tab.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

// S1.4 批次 1 冒烟：应用壳三 Tab 导航 + Gallery 隐藏入口
// 页面含极光常驻动画，只 pump 固定帧，禁 pumpAndSettle
void main() {
  testWidgets("应用壳：默认歌单 Tab，可切广场/设置", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    expect(container.read(homeTabControllerProvider), HomeTab.playlists);

    // Dock 切广场（页面标题是"音乐广场"，与 Dock 文案"广场"不冲突）
    await tester.tap(find.text("广场"));
    await tester.pump();
    expect(container.read(homeTabControllerProvider), HomeTab.plaza);

    // 切设置
    await tester.tap(find.text("设置"));
    await tester.pump();
    expect(container.read(homeTabControllerProvider), HomeTab.settings);
  });

  testWidgets("设置页长按版本行 → 进入组件 Gallery（隐藏入口）", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    await tester.tap(find.text("设置"));
    await tester.pump();
    await tester.longPress(find.text("检查更新"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("S1.3 · 全局组件"), findsOneWidget);
  });

  testWidgets("歌单页组件陈列：快捷入口/歌单行/歌曲行", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    expect(find.text("我的歌单"), findsOneWidget);
    expect(find.text("本地音乐"), findsOneWidget);
    expect(find.text("我喜欢的音乐"), findsOneWidget);
    expect(find.text("夜色轻电子"), findsOneWidget);
    expect(find.text("夜航西飞"), findsOneWidget);
  });

  testWidgets("窄视口（390dp）切广场：合集卡片无溢出（回归）", (WidgetTester tester) async {
    // 真机宽度才暴露的溢出（测试默认视口 800 宽不会触发）
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
