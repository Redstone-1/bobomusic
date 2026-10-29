import "dart:async";

import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/data/local_audio_scanner.dart";
import "package:bobomusic/features/playlist/local_scan_controller.dart";
import "package:bobomusic/features/playlist/local_scan_panel.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

/// 扫描舱：完整路径文件流 + 取消按钮（不走真实文件系统）
void main() {
  testWidgets("扫描舱显示完整路径与取消按钮", (WidgetTester tester) async {
    final events = StreamController<LocalScanEvent>();
    final controller = LocalScanController(
      taskFactory: () =>
          LocalScanTask(events: events.stream, cancel: events.close),
      syncTracks: (_) async {},
    );
    addTearDown(controller.dispose);

    final tokens = buildAuroraTokens(
      AppThemeColor.natureGreen,
      Brightness.dark,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [tokens], useMaterial3: true),
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: LocalScanPanel(
              controller: controller,
              onCancel: controller.cancel,
            ),
          ),
        ),
      ),
    );

    final started = controller.start();
    events.add(
      const LocalScanFiles(["/storage/emulated/0/Music/薛之谦/我好像在哪见过你.mp3"]),
    );
    events.add(const LocalScanProgress(scanned: 1, indexed: 1, failed: 0));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text("正在扫描本地音乐"), findsOneWidget);
    expect(
      find.text("/storage/emulated/0/Music/薛之谦/我好像在哪见过你.mp3"),
      findsOneWidget,
    );
    expect(find.text("取消扫描"), findsOneWidget);

    await tester.tap(find.text("取消扫描"));
    await tester.pump();
    await started;

    expect(controller.phase, LocalScanPhase.idle);
    expect(controller.cancelled, isTrue);
  });
}
