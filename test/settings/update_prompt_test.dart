import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/features/settings/update_checker.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

/// 固定结果的检查更新替身：result 为 null 时模拟网络失败
class _FakeUpdateChecker extends UpdateChecker {
  _FakeUpdateChecker(this.result);
  final UpdateResult? result;

  @override
  Future<UpdateResult> check(String currentVersion) async {
    if (result == null) throw StateError("网络不可用");
    return result!;
  }
}

UpdateResult _result({required bool hasUpdate, String notes = ""}) =>
    UpdateResult(
      currentVersion: "3.0.1",
      latest: hasUpdate
          ? AppRelease(
              version: "9.9.9",
              tag: "v9.9.9",
              url: "https://example.com/releases/v9.9.9",
              notes: notes,
              publishedAt: "2026-11-03",
            )
          : null,
      hasUpdate: hasUpdate,
    );

Future<void> _pumpApp(WidgetTester tester, UpdateChecker checker) async {
  updateChecker = checker;
  addTearDown(() => updateChecker = UpdateChecker());
  await tester.pumpWidget(await buildTestApp(launchUpdateCheck: true));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
  await tester.pump();
  // 壳首帧调度 → 2s 延迟到期 → 静默检查返回 → 弹窗进场
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _dialogContent() => find.descendant(
    of: find.byType(Dialog), matching: find.byType(SingleChildScrollView));

void main() {
  testWidgets("启动静默检测：有新版本弹窗，短内容自适应高度", (tester) async {
    await _pumpApp(
      tester,
      _FakeUpdateChecker(_result(hasUpdate: true, notes: "修复若干问题")),
    );
    expect(find.text("发现新版本 9.9.9"), findsOneWidget);
    // 回归旧固定 200 高：内容只有一行时弹窗应收缩包裹
    expect(tester.getRect(_dialogContent()).height, lessThan(200));
    await tester.tap(find.text("稍后"));
    // 先推一帧让退出动画启动，再走完时长确认路由移除
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("发现新版本 9.9.9"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("超长更新内容封顶 320 滚动", (tester) async {
    final notes =
        List.generate(60, (i) => "第$i条更新说明，内容较长用于撑高弹窗").join("\n");
    await _pumpApp(
      tester,
      _FakeUpdateChecker(_result(hasUpdate: true, notes: notes)),
    );
    expect(tester.getRect(_dialogContent()).height, closeTo(320, 0.5));
    await tester.tap(find.text("稍后"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets("无新版本保持安静", (tester) async {
    await _pumpApp(tester, _FakeUpdateChecker(_result(hasUpdate: false)));
    expect(find.text("发现新版本 9.9.9"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("检查失败静默不崩溃", (tester) async {
    await _pumpApp(tester, _FakeUpdateChecker(null));
    expect(find.text("发现新版本 9.9.9"), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
