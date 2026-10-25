import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/widgets/theme_swatch.dart";
import "package:bobomusic/features/home/home_tab.dart";
import "package:bobomusic/features/player/mock_playback.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "helpers/app_test_helper.dart";

// S1.4 批次 1 冒烟：应用壳三 Tab 导航 + Gallery 隐藏入口
// 页面含极光常驻动画，只 pump 固定帧，禁 pumpAndSettle
void main() {
  testWidgets("应用壳：默认歌单 Tab，可切广场/设置", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
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
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("设置"));
    await tester.pump();
    await tester.longPress(find.text("检查更新"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("S1.3 · 全局组件"), findsOneWidget);
  });

  testWidgets("歌单页：真数据空库 → 空态 + 快捷卡", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 仓库 Future 完成

    expect(find.text("我的歌单"), findsOneWidget);
    expect(find.text("本地音乐"), findsOneWidget);
    expect(find.text("我喜欢的音乐"), findsOneWidget);
    expect(find.text("还没有歌单"), findsOneWidget); // 空库 → 分区空态
    expect(find.text("播放队列是空的"), findsOneWidget);
  });

  testWidgets("点歌曲只开播（迷你条在场），点迷你条才弹播放卡", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 热门歌手资源加载
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    const firstSingerTrackId = "612255353_BV1e84y1T7jp_1088807591";

    // 广场 → 热门歌手（chinese.json）→ 歌手详情
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("周杰伦"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 详情第一首 → 只开播，详情页迷你条在场
    await tester.tap(find.textContaining("夜曲"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsNothing); // 播放卡未弹
    expect(find.byKey(const Key("mini_player")), findsOneWidget);
    expect(container.read(mockPlaybackProvider).playing, isTrue);

    // 点迷你条 → 弹播放卡
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsOneWidget);

    // 暂停 → 下一首（mock 引擎跳出歌手曲目属预期）
    await tester.tap(find.byKey(const Key("player_play")));
    await tester.pump();
    expect(container.read(mockPlaybackProvider).playing, isFalse);
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    expect(
      container.read(mockPlaybackProvider).track?.id,
      isNot(firstSingerTrackId),
    );

    // 收起 → 迷你条仍在
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

    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets("歌单 CRUD：创建 → 打开空详情 → 删除", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 创建（+ → 输入弹窗）
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField), "测试歌单");
    await tester.tap(find.text("确定"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("测试歌单"), findsOneWidget);

    // 打开详情（空库 → 空态）
    await tester.tap(find.text("测试歌单"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("歌单还是空的"), findsOneWidget);

    await tester.tap(find.text("返回"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 删除：kebab → sheet → 危险确认
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("删除歌单"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text("删除"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("测试歌单"), findsNothing);
  });

  testWidgets("搜索页：空态 → 输入 → 单曲/歌单分区", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.tap(find.text("搜索歌曲 / 歌手 / 合集"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // 空态
    expect(find.text("输入关键词开始搜索"), findsOneWidget);

    // 过滤：夜 → 单曲（夜航西飞）+ 多P歌单（华语民谣·深夜电台）双分区
    await tester.enterText(find.byType(TextField), "夜");
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text("夜航西飞"), findsOneWidget);
    expect(find.text("华语民谣·深夜电台"), findsOneWidget);
    expect(find.text("没有找到相关的内容"), findsNothing);
  });

  testWidgets("收藏合集闭环：搜索 → 收藏 → 广场展示 → 详情", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 广场初始空态
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("还没有收藏合集"), findsOneWidget);

    // 去搜索 → 输入 → 防抖后出结果
    await tester.tap(find.text("去搜索"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), "民谣");
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // 收藏多P歌单结果
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 返回广场 → 合集卡片在场（折叠线以下，先拖进来）
    await tester.tap(find.text("返回"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("华语民谣·深夜电台"), findsOneWidget);
    await tester.drag(find.text("热门歌手"), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 点卡片 → 合集详情
    await tester.tap(find.text("华语民谣·深夜电台"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("加入待播放"), findsOneWidget);
  });

  testWidgets("播放卡：歌词视图切换与播放队列", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );

    // 开播并进入播放卡（广场 → 歌手详情 → 第一首 → 迷你条 → 播放卡）
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("周杰伦"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.textContaining("夜曲"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 切歌词视图：mock 歌词行在场
    await tester.tap(find.text("歌词"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("仿佛如同一场梦"), findsOneWidget);

    // 切回黑胶
    await tester.tap(find.text("歌词"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("仿佛如同一场梦"), findsNothing);

    // 打开播放队列 sheet
    await tester.tap(find.byKey(const Key("player_queue")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("播放队列 · 8 首"), findsOneWidget);

    // 点队列中的曲目切歌，sheet 关闭
    await tester.tap(find.text("起风了"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(mockPlaybackProvider).track?.name, "起风了");
    expect(find.text("播放队列 · 8 首"), findsNothing);
  });

  testWidgets("主题色/明暗选择持久化写回 appPrefs", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("设置"));
    await tester.pump();
    // 第二个色点（晚霞红）→ theme_color 写回
    await tester.tap(find.byType(ThemeSwatch).at(1));
    await tester.pump();
    expect(appPrefs.getString("theme_color"), "sunsetRed");

    // 浅色分段 → theme_mode 写回
    await tester.tap(find.text("浅色"));
    await tester.pump();
    expect(appPrefs.getString("theme_mode"), "light");
  });

  testWidgets("重启读回：带初值启动时主题随之生效", (WidgetTester tester) async {
    await tester.pumpWidget(
      await buildTestApp(
        prefs: {"theme_color": "sunsetRed", "theme_mode": "light"},
      ),
    );
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    final expected =
        buildAuroraTokens(AppThemeColor.sunsetRed, Brightness.light).primary;
    expect(app.theme?.colorScheme.primary, expected);
  });
}
