import "package:bobomusic/app/app.dart";
import "package:bobomusic/features/home/home_tab.dart";
import "package:bobomusic/features/player/mock_playback.dart";
import "package:flutter/material.dart";
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

  testWidgets("点歌曲只开播（迷你条在场），点迷你条才弹播放卡", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );

    // 点最近播放第一行（先拖进视口）→ 只开播，不弹卡
    await tester.drag(find.text("自定义歌单"), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("夜航西飞"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsNothing); // 播放卡未弹
    expect(find.byKey(const Key("mini_player")), findsOneWidget); // 迷你条在场
    expect(container.read(mockPlaybackProvider).playing, isTrue);
    // mock 快进已起步（120ms/步）
    expect(container.read(mockPlaybackProvider).progress, greaterThan(0));

    // 点迷你条 → 弹播放卡
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsOneWidget);

    // 暂停 → 下一首
    await tester.tap(find.byKey(const Key("player_play")));
    await tester.pump();
    expect(container.read(mockPlaybackProvider).playing, isFalse);
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    expect(container.read(mockPlaybackProvider).track?.name, "漠河舞厅");

    // 收起 → 回到壳，迷你条在场
    await tester.tap(find.byKey(const Key("player_close")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsNothing);
    expect(find.byKey(const Key("mini_player")), findsOneWidget);

    // 迷你条播放键恢复播放
    await tester.tap(find.byKey(const Key("mini_play")));
    await tester.pump();
    expect(container.read(mockPlaybackProvider).playing, isTrue);
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

  testWidgets("歌单行 → 歌单详情 → 返回", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    await tester.tap(find.text("夜色轻电子"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // 详情页副题唯一包含"播放全部"字样
    expect(find.textContaining("播放全部"), findsOneWidget);

    await tester.tap(find.text("返回"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining("· 播放全部"), findsNothing);
  });

  testWidgets("合集卡 → 合集详情", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    // 合集区在折叠线以下，先拖进来再点
    await tester.drag(find.text("热门歌手"), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("华语民谣·深夜电台"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("加入待播放"), findsOneWidget);
  });

  testWidgets("搜索页：空态 → 输入过滤", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.tap(find.text("搜索歌曲 / 歌手 / 合集"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // 空态
    expect(find.text("输入关键词开始搜索"), findsOneWidget);

    // 过滤：夜 → 仅夜航西飞命中（1 首）
    await tester.enterText(find.byType(TextField), "夜");
    await tester.pump();
    expect(find.text("1 首"), findsOneWidget);
    expect(find.text("没有找到相关的内容"), findsNothing);
  });
}
