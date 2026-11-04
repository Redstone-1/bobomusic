import "package:bobomusic/core/widgets/app_search_field.dart";
import "package:bobomusic/core/widgets/glass_card.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<Map<String, Object?>> _searchAppearance(
    WidgetTester tester, String hint) async {
  final search = find.byType(AppSearchField);
  expect(search, findsOneWidget);
  final field = find.descendant(of: search, matching: find.byType(TextField));
  final card = tester.widget<GlassCard>(
      find.descendant(of: search, matching: find.byType(GlassCard)));
  final textField = tester.widget<TextField>(field);
  expect(textField.decoration!.hintText, hint);
  final appearance = <String, Object?>{
    "size": tester.getSize(search),
    "radius": card.radius,
    "padding": card.padding,
    "frosted": card.frosted,
    "textStyle": textField.style,
    "hintStyle": textField.decoration!.hintStyle,
  };
  await tester.enterText(field, "不会命中的关键词");
  tester.view.viewInsets = const FakeViewPadding(bottom: 280);
  await _frames(tester);
  final decorator = tester.widget<InputDecorator>(
      find.descendant(of: search, matching: find.byType(InputDecorator)));
  expect(decorator.isFocused, isTrue);
  expect(decorator.decoration.focusedBorder, InputBorder.none);
  expect(tester.getSize(search), appearance["size"]);
  await tester.tap(find.byTooltip("清除搜索"));
  await tester.pump();
  expect(textField.controller!.text, isEmpty);
  expect(find.byTooltip("清除搜索"), findsNothing);
  tester.view.resetViewInsets();
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await _frames(tester);
  expect(tester.takeException(), isNull);
  return appearance;
}

void main() {
  for (final mode in ["light", "dark"]) {
    testWidgets("$mode 本地、喜欢、全部歌单的搜索框外观和清除交互一致", (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final app = await buildTestApp(prefs: {
        "theme_mode": mode
      }, seedTracks: const [
        {"id": "a", "name": "晴天", "author": "周杰伦"},
      ]);
      await TrackRepository().setLiked("a", true);
      for (var i = 0; i < 4; i++) {
        await PlaylistRepository().create("歌单$i");
      }
      await tester.pumpWidget(app);
      await _frames(tester);
      await tester.tap(find.text("本地音乐"));
      await _frames(tester);
      final baseline = await _searchAppearance(tester, "搜索歌曲 / 歌手");
      Navigator.of(tester.element(find.byType(AppSearchField))).pop();
      await _frames(tester);
      await tester.tap(find.text("我喜欢的音乐"));
      await _frames(tester);
      expect(await _searchAppearance(tester, "搜索歌曲 / 歌手"), baseline);
      Navigator.of(tester.element(find.byType(AppSearchField))).pop();
      await _frames(tester);
      await tester.tap(find.text("更多"));
      await _frames(tester);
      expect(await _searchAppearance(tester, "搜索歌单名称"), baseline);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await appDb.close();
    });
  }
}
