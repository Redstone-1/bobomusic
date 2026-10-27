import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/empty_state.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:flutter_test/flutter_test.dart";

/// 空态插画资源冒烟：5 张 undraw SVG 必须能被 flutter_svg 解析渲染
/// （文件在打包/提取环节损坏时在此暴露，而不是运行时空态白块）
void main() {
  const assets = [
    "assets/illustrations/empty_music.svg",
    "assets/illustrations/empty_local_music.svg",
    "assets/illustrations/empty_collection.svg",
    "assets/illustrations/empty_search.svg",
    "assets/illustrations/empty_download.svg",
  ];

  for (final asset in assets) {
    testWidgets("插画解析渲染：$asset", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          // EmptyState 依赖 AuroraTokens 主题扩展
          theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.light),
          home: Scaffold(
            body: EmptyState(asset: asset, title: "测试"),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
