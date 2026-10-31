import "package:bobomusic/core/overlays/app_dialog.dart";
import "package:bobomusic/core/overlays/app_loading.dart";
import "package:bobomusic/core/overlays/app_sheet.dart";
import "package:bobomusic/core/overlays/app_toast.dart";
import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/aurora_progress_bar.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "helpers/app_test_helper.dart";

// S1.3 全局组件冒烟：弹窗 / 操作面板 / Toast / 进度条
// 验证页含常驻动画，统一只 pump 固定帧
// overlay 调用约定：context 必须能找到 Navigator（同时必然拥有主题 token），
// 所以这里取 MaterialApp 之下的 Scaffold 元素 context，而不是 App 根 context
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(await buildTestApp());
  await tester.pump();
}

BuildContext _appContext(WidgetTester tester) =>
    tester.element(find.byType(Scaffold));

// 验证页含极光/均衡器常驻动画，禁用 pumpAndSettle（永不 settle），改固定时长推进
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  testWidgets("确认弹窗：确定返回 true / 取消返回 false", (WidgetTester tester) async {
    var result = false;
    await _pumpApp(tester);
    final buildContext = _appContext(tester);

    final future = AppDialog.confirm(
      buildContext,
      title: "删除歌单",
      message: "确认？",
      danger: true,
      confirmText: "删除",
    ).then((v) => result = v);

    await _settle(tester);
    await tester.tap(find.text("删除"));
    await _settle(tester);
    await future;
    expect(result, isTrue);

    // 再来一次：取消（.then 回写 result）
    final future2 = AppDialog.confirm(
      buildContext,
      title: "确认？",
    ).then((v) => result = v);
    await _settle(tester);
    await tester.tap(find.text("取消"));
    await _settle(tester);
    await future2;
    expect(result, isFalse);
  });

  testWidgets("输入弹窗：输入文本后确定返回文本", (WidgetTester tester) async {
    String? result;
    await _pumpApp(tester);
    final buildContext = _appContext(tester);

    final future = AppDialog.input(
      buildContext,
      title: "新建歌单",
      hint: "歌单名",
    ).then((v) => result = v);

    await _settle(tester);
    await tester.enterText(find.byType(TextFormField), "雨天钢琴");
    await tester.tap(find.text("确定"));
    await _settle(tester);
    await future;
    expect(result, "雨天钢琴");
  });

  testWidgets("输入弹窗：空文本校验不通过，不关闭", (WidgetTester tester) async {
    var resolved = false;
    await _pumpApp(tester);
    final buildContext = _appContext(tester);

    AppDialog.input(
      buildContext,
      title: "新建歌单",
      validator: (v) => (v == null || v.trim().isEmpty) ? "不能为空" : null,
    ).then((_) => resolved = true);

    await _settle(tester);
    await tester.tap(find.text("确定"));
    await tester.pump();
    expect(find.text("不能为空"), findsOneWidget);
    expect(resolved, isFalse);
  });

  testWidgets("操作面板：点选项后回调并关闭", (WidgetTester tester) async {
    var picked = false;
    await _pumpApp(tester);
    final buildContext = _appContext(tester);

    AppSheet.show(
      buildContext,
      title: "夜航西飞",
      actions: [
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: "下一首播放",
          onTap: () => picked = true,
        ),
      ],
    );

    await _settle(tester);
    expect(find.text("下一首播放"), findsOneWidget);
    await tester.tap(find.text("下一首播放"));
    await _settle(tester);
    expect(picked, isTrue);
    expect(find.text("下一首播放"), findsNothing);
  });

  testWidgets("Toast：顶部弹出后文案可见，2 秒后消失", (WidgetTester tester) async {
    await _pumpApp(tester);
    final buildContext = _appContext(tester);

    AppToast.show(buildContext, "已加入播放队列");
    // BotToast 插入两帧完成：先一帧入树，再一帧推进入场动画
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("已加入播放队列"), findsOneWidget);

    // 默认 2s 自动消失（计时器触发后还有退场动画，再补一帧）
    await tester.pump(const Duration(seconds: 2, milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("已加入播放队列"), findsNothing);
  });

  testWidgets("加载态：show 显示、dismiss 关闭", (WidgetTester tester) async {
    await _pumpApp(tester);

    AppLoading.show(msg: "正在加载…");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("正在加载…"), findsOneWidget);

    AppLoading.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("正在加载…"), findsNothing);
  });

  testWidgets("进度条：点按提交、拖动松手才提交一次", (WidgetTester tester) async {
    double? tapped;
    double? previewed;
    await tester.pumpWidget(
      MaterialApp(
        // 必须用带 AuroraTokens 扩展的主题（AuroraTokens.of 依赖注入）
        theme: buildAppTheme(AppThemeColor.oceanBlue, Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: AuroraProgressBar(
                value: 0,
                onChanged: (v) => tapped = v,
                onPreviewChanged: (v) => previewed = v,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuroraProgressBar));
    expect(tapped, closeTo(0.5, 0.05));
    tapped = null;

    // 拖动过程只上报预览、不提交（引擎旧位置会把拖点拉回的根因），
    // 松手按最后拖动位置提交一次
    final center = tester.getCenter(find.byType(AuroraProgressBar));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    // 手势竞技场胜出的首个 move 事件只触发 dragStart，补一次 move 触发 dragUpdate
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(previewed, closeTo(0.755, 0.05));
    expect(tapped, isNull);
    await gesture.up();
    await tester.pump();
    expect(tapped, closeTo(0.755, 0.05));
  });
}
