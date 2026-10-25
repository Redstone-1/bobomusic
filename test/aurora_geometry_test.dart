import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/widgets/aurora_background.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

/// 极光背景几何回归：三球直径按屏宽等比（s = w/375）且真实生效
/// 背景：StackFit.expand 的 tight 约束曾把光斑 SizedBox 压成全屏内切圆，
/// 直径参数完全失效（宽屏上球体跑偏、看似"消失"）
void main() {
  Future<List<Size>> blobSizes(WidgetTester tester, Size viewport) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: [
            buildAuroraTokens(AppThemeColor.oceanBlue, Brightness.dark),
          ],
        ),
        home: const Scaffold(
          body: AuroraBackground(
            animated: false,
            child: SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();
    final boxes = find
        .descendant(
          of: find.byType(AuroraBackground),
          matching: find.byType(SizedBox),
        )
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .toList();
    // 前 3 个 SizedBox = 三枚光斑（第 4 个是传入的 child）
    return boxes.take(3).map((b) => b.size).toList();
  }

  testWidgets("375 设计稿宽：三球直径生效（原型 340/300/360 ×1.5）", (tester) async {
    final sizes = await blobSizes(tester, const Size(375, 812));
    expect(sizes[0], const Size(510, 510));
    expect(sizes[1], const Size(450, 450));
    expect(sizes[2], const Size(540, 540));
  });

  testWidgets("390 宽屏手机：直径等比放大（s≈1.04）", (tester) async {
    final s = 390 / 375;
    final sizes = await blobSizes(tester, const Size(390, 844));
    expect(sizes[0].width, closeTo(510 * s, 0.5));
    expect(sizes[1].width, closeTo(450 * s, 0.5));
    expect(sizes[2].width, closeTo(540 * s, 0.5));
    // 回归锚点：直径必须不等于全屏内切圆（旧 bug 场景）
    expect(sizes[2].width, isNot(390));
  });

  testWidgets("1280 桌面宽窗：直径随宽度放大铺满", (tester) async {
    final s = 1280 / 375;
    final sizes = await blobSizes(tester, const Size(1280, 720));
    expect(sizes[0].width, closeTo(510 * s, 0.5));
    expect(sizes[2].width, closeTo(540 * s, 0.5));
  });
}
