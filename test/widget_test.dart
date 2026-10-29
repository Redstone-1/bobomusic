import "package:bobomusic/app/app.dart";
import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/data/local_audio_scanner.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/core/widgets/eq_bars.dart";
import "package:bobomusic/core/widgets/theme_swatch.dart";
import "package:bobomusic/features/home/home_tab.dart";
import "package:bobomusic/features/player/playback_provider.dart";
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
    // 检查更新已移到卡片最后一项，默认视口内不可见，需先滚到它
    // （scrollable 必须限定设置页自身——IndexedStack 保活其它 Tab 的滚动器）
    await tester.scrollUntilVisible(
      find.text("检查更新"),
      200,
      scrollable: find
          .ancestor(
            of: find.text("主题 · 外观 · 关于"),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    expect(find.text("还没有播放记录"), findsOneWidget);
  });

  testWidgets("歌单页下载入口 → 下载管理空态", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key("downloads_entry")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("下载管理"), findsOneWidget);
    expect(find.text("还没有下载"), findsOneWidget);
    expect(find.text("下载中 0"), findsOneWidget);
  });

  testWidgets("广场榜单列表点行开播（迷你条在场），点迷你条才弹播放卡", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );

    // 广场 → 热歌榜列表（默认选中）→ 点行开播
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 榜单加载
    expect(find.text("酷我热歌榜"), findsOneWidget); // Tab
    await tester.tap(find.text("酷我热歌").first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text("正在播放"), findsNothing); // 播放卡未弹
    expect(find.byKey(const Key("mini_player")), findsOneWidget);
    expect(find.byKey(const Key("mini_prev")), findsOneWidget);
    expect(find.byKey(const Key("mini_next")), findsOneWidget);
    expect(container.read(playbackProvider).track?.id, "kuwo:hot_1");
    // 单句歌词按播放位置取当前行（6s → 第二行），验证刷新同步
    fakePlaybackEngine!.emitPosition(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text("我们如此短暂地相逢"), findsOneWidget);
    expect(container.read(playbackProvider).playing, isTrue);

    // 点迷你条 → 弹播放卡；暂停后收起
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsOneWidget);
    await tester.tap(find.byKey(const Key("player_play")));
    await tester.pump();
    expect(container.read(playbackProvider).playing, isFalse);

    await tester.tap(find.byKey(const Key("player_close")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("正在播放"), findsNothing);
    expect(find.byKey(const Key("mini_player")), findsOneWidget);

    // 迷你条播放键可恢复播放
    await tester.tap(find.byKey(const Key("mini_play")));
    await tester.pump();
    expect(container.read(playbackProvider).playing, isTrue);
  });

  testWidgets("窄视口（390dp）切广场：榜单 chips 与列表无溢出（回归）", (WidgetTester tester) async {
    // 真机宽度才暴露的溢出（测试默认视口 800 宽不会触发）
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("酷我热歌榜"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("广场榜单 Tab：多源榜单可切换，切网易榜列表换内容", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 五张榜单 Tab（酷我 x2 + 网易 x2 + 千千 x1；B 站音乐榜已下线，QQ 榜未上）
    expect(find.text("酷我热歌榜"), findsOneWidget);
    expect(find.text("酷我飙升榜"), findsOneWidget);
    expect(find.text("网易云热歌榜"), findsOneWidget);
    expect(find.text("网易云飙升榜"), findsOneWidget);
    expect(find.text("千千新歌榜"), findsOneWidget);

    // 切到网易热歌榜：列表换为网易 Fake 数据（Tab 动画 + provider 重建需多帧）
    await tester.tap(find.text("网易云热歌榜"));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text("网易云热歌榜"), findsOneWidget); // Tab
    expect(find.text("网易热歌"), findsWidgets);
  });

  testWidgets("广场榜单未播放：不显示波浪动效", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 未播放时榜单行不能因为 item/current 都是 null 而误判为播放中
    expect(find.byType(EqBars), findsNothing);
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

  testWidgets("搜索页切换酷我音源：结果来自酷我", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.tap(find.text("搜索歌曲 / 歌手 / 合集"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 默认 B 站；改为酷我后重搜
    await tester.tap(find.text("酷我"));
    await tester.pump();
    await tester.enterText(find.byType(TextField), "夜");
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text("酷我夜曲"), findsOneWidget);
    expect(find.text("夜航西飞"), findsNothing); // 切到酷我后不走 B 站
  });

  testWidgets("播放卡：默认歌词", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    // 广场 → 榜单列表点行开播 → 迷你条 → 播放卡
    await tester.tap(find.text("广场"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text("酷我热歌").first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 播放卡默认就是歌词视图（不再有黑胶/PageView）
    expect(find.byKey(const Key("player_pager")), findsNothing);
    expect(find.byKey(const Key("player_lyrics")), findsOneWidget);
    fakePlaybackEngine!.emitPosition(const Duration(seconds: 6));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key("player_lyrics")),
        matching: find.text("我们如此短暂地相逢"),
      ),
      findsOneWidget,
    );
  });

  testWidgets("默认主题色为青绿色（natureGreen）", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final expected = buildAuroraTokens(
      AppThemeColor.natureGreen,
      Brightness.light,
    ).primary;
    expect(app.theme?.colorScheme.primary, expected);
    expect(appPrefs.getString("theme_color"), isNull);
  });

  testWidgets("主题色/明暗选择持久化写回 appPrefs", (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pump();

    await tester.tap(find.text("设置"));
    await tester.pump();
    // 第三个色点（晚霞红——默认已是青绿色，只有选不同色才写盘）
    await tester.tap(find.byType(ThemeSwatch).at(2));
    await tester.pump();
    expect(appPrefs.getString("theme_color"), "sunsetRed");

    // 标题右侧图标切换明暗，仍写回原有偏好。
    await tester.tap(find.byTooltip("切换为深色"));
    await tester.pump();
    expect(appPrefs.getString("theme_mode"), "dark");
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
