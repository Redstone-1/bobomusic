import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/data/local_audio_scanner.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/core/widgets/song_list_tile.dart";
import "package:bobomusic/core/widgets/theme_swatch.dart";
import "package:bobomusic/features/home/home_tab.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/plaza/singer_list_page.dart";
import "package:bobomusic/features/playlist/playlist_detail_page.dart";
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
    const firstSingerTrackId = "s1_t1"; // mock 歌手周杰伦首曲

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
    expect(container.read(playbackProvider).playing, isTrue);

    // 点迷你条 → 弹播放卡
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsOneWidget);

    // 暂停 → 下一首（会话队列内切到同歌手下一首）
    await tester.tap(find.byKey(const Key("player_play")));
    await tester.pump();
    expect(container.read(playbackProvider).playing, isFalse);
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 引擎装载微任务
    expect(
      container.read(playbackProvider).track?.id,
      isNot(firstSingerTrackId),
    );

    // 收起 → 迷你条仍在
    await tester.tap(find.byKey(const Key("player_close")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsNothing);
    expect(find.byKey(const Key("mini_player")), findsOneWidget);

    // 切歌自动续播；迷你条播放键可再暂停
    expect(container.read(playbackProvider).playing, isTrue);
    await tester.tap(find.byKey(const Key("mini_play")));
    await tester.pump();
    expect(container.read(playbackProvider).playing, isFalse);
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

  testWidgets("广场更多 → 歌手列表 → 歌手详情（对齐 2.7.0）", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 热门歌手资源加载

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 「更多」→ 歌手列表页（广场头像同名文案在下层路由，用 descendant 限定）
    await tester.tap(find.text("更多"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final listPage = find.byType(SingerListPage);
    expect(listPage, findsOneWidget);
    expect(
      find.descendant(of: listPage, matching: find.text("周杰伦")),
      findsOneWidget,
    );
    expect(
      find.descendant(of: listPage, matching: find.text("柳爽")),
      findsOneWidget,
    );

    // 点歌手 → 歌单详情（内存注入曲目，副题回退曲目数「1 首」）
    await tester.tap(find.descendant(of: listPage, matching: find.text("柳爽")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("漠河舞厅"), findsOneWidget);
    // 曲目行统一用歌手封面（与广场头像同源），不用各行自身封面
    final detailTiles = find.descendant(
      of: find.byType(PlaylistDetailPage),
      matching: find.byType(SongListTile),
    );
    expect(
      tester.widget<SongListTile>(detailTiles).coverOverride,
      "https://example.com/liushuang.jpg",
    );
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

  testWidgets("本地音乐扫描闭环：空态 → 扫描 → 列表与计数更新", (WidgetTester tester) async {
    // 扫描器可替换全局：跳权限/文件系统/Isolate（host 平台权限层本就直接放行）
    localScanTestOverride = const LocalScanResult(
      tracks: [
        Track(
          id: "local:1:211:漠河舞厅:柳爽",
          name: "漠河舞厅",
          author: "柳爽",
          duration: 211,
          origin: OriginType.local,
          localPath: "/music/a.mp3",
        ),
        Track(
          id: "local:2:227:夜曲:周杰伦",
          name: "夜曲",
          author: "周杰伦",
          duration: 227,
          origin: OriginType.local,
          localPath: "/music/b.mp3",
        ),
      ],
      failed: [],
    );
    addTearDown(() => localScanTestOverride = null);

    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("待扫描"), findsOneWidget); // 快捷卡 0 首引导

    // 进本地音乐详情 → 空态 → 扫描
    await tester.tap(find.text("本地音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("本地音乐是空的"), findsOneWidget);
    await tester.tap(find.text("扫描本地音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("漠河舞厅"), findsOneWidget);
    expect(find.text("夜曲"), findsOneWidget);
    expect(find.text("扫描完成 · 共 2 首"), findsOneWidget);

    // 返回歌单页：快捷卡计数已刷新
    await tester.tap(find.text("返回"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("2 首"), findsOneWidget);
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
    // 竖屏真机视口：宽松空态下移后，800×600 横向视口的「去搜索」会被底部 Dock 遮挡
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // 打开播放队列 sheet（会话队列 = 歌手歌单 2 首）
    await tester.tap(find.byKey(const Key("player_queue")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("播放队列 · 2 首"), findsOneWidget);

    // 点队列中的曲目切歌，sheet 关闭
    await tester.tap(find.text("七里香"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(playbackProvider).track?.name, "七里香");
    expect(find.text("播放队列 · 2 首"), findsNothing);
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
