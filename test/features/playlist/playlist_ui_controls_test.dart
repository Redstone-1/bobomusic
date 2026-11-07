import "package:bobomusic/core/widgets/app_checkbox_row.dart";
import "package:bobomusic/core/widgets/app_form_field.dart";
import "package:bobomusic/core/theme/aurora_tokens.dart";
import "package:bobomusic/data/db/app_database.dart";
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/playback_provider.dart";
import "package:bobomusic/features/playlist/batch_rename_page.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<String> _openPlaylist(WidgetTester tester,
    {String mode = "light"}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  final app = await buildTestApp(prefs: {
    "theme_mode": mode
  }, seedTracks: const [
    {"id": "a", "name": "01周杰伦-晴天", "author": ""},
    {"id": "b", "name": "02周杰伦-手写的从前", "author": ""},
    {"id": "c", "name": "普通歌名", "author": ""},
  ]);
  final playlist = await PlaylistRepository().create("界面回归");
  for (final id in ["a", "b", "c"]) {
    await PlaylistRepository().addTrack(playlist.id, id);
  }
  await tester.pumpWidget(app);
  await _frames(tester);
  await tester.tap(find.text("界面回归"));
  await _frames(tester);
  return playlist.id;
}

Future<void> _playlistMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(const Key("custom_playlist_more")));
  await _frames(tester);
  await tester.tap(find.text(action));
  await _frames(tester);
}

Map<String, Object?> _fieldStyle(WidgetTester tester, String label) {
  final field = find.widgetWithText(AppFormField, label);
  final input = tester.widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)));
  expect(input.decoration!.enabledBorder, isA<OutlineInputBorder>());
  expect(input.decoration!.focusedBorder, isA<OutlineInputBorder>());
  expect(input.decoration!.filled, isTrue);
  return {
    "style": input.style,
    "padding": input.decoration!.contentPadding,
    "border": input.decoration!.enabledBorder,
    "focusedBorder": input.decoration!.focusedBorder,
    "fill": input.decoration!.fillColor,
    "labelStyle": input.decoration!.labelStyle
  };
}

double _cancelBottomInset(WidgetTester tester) {
  final button =
      find.ancestor(of: find.text("取消"), matching: find.byType(TextButton));
  return tester.getRect(find.byKey(const Key("app_dialog_panel"))).bottom -
      tester.getRect(button).bottom;
}

void main() {
  for (final mode in ["light", "dark"]) {
    testWidgets("$mode 歌单、建议和规则沿用既有输入样式，封面复选框可独立点击并校验", (tester) async {
      final playlistId = await _openPlaylist(tester, mode: mode);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _frames(tester);
      await tester.tap(find.text("编辑信息"));
      await _frames(tester);
      final baseline = _fieldStyle(tester, "歌名");
      final bottomInset = _cancelBottomInset(tester);
      await tester.tap(find.text("取消"));
      await _frames(tester);
      await _playlistMenu(tester, "编辑信息");
      expect(_fieldStyle(tester, "歌单名称"), baseline);
      expect(_fieldStyle(tester, "封面图片链接"), baseline);
      expect(_cancelBottomInset(tester), closeTo(bottomInset, 0.1));
      final check = find.byKey(const Key("playlist_apply_cover"));
      final box = find.descendant(of: check, matching: find.byType(Checkbox));
      final label = find.text("将歌单封面应用到此歌单的全部歌曲");
      expect(tester.getTopLeft(label).dx - tester.getTopRight(box).dx,
          lessThanOrEqualTo(8));
      await tester.tap(box);
      await tester.pump();
      expect(tester.widget<AppCheckboxRow>(check).value, isTrue);
      await tester.tap(label);
      await tester.pump();
      expect(tester.widget<AppCheckboxRow>(check).value, isFalse);
      await tester.tap(box);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key("playlist_edit_save")));
      await tester.tap(find.byKey(const Key("playlist_edit_save")));
      await _frames(tester);
      expect(find.text("请先选择图片或填写图片链接"), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect((await PlaylistRepository().getById(playlistId))!.customCover,
          isNull);
      await tester.tap(find.text("取消"));
      await _frames(tester);
      await _playlistMenu(tester, "批量重命名");
      final ruleInput = tester.widget<InputDecorator>(find.descendant(
          of: find.byKey(const Key("rename_rule")),
          matching: find.byType(InputDecorator)));
      expect(ruleInput.decoration.enabledBorder, baseline["border"]);
      expect(ruleInput.decoration.contentPadding, baseline["padding"]);
      expect(ruleInput.decoration.fillColor, baseline["fill"]);
      await tester.tap(find.byKey(const ValueKey("rename_edit_a")));
      await _frames(tester);
      expect(_fieldStyle(tester, "建议歌名"), baseline);
      expect(_fieldStyle(tester, "建议歌手"), baseline);
      expect(_cancelBottomInset(tester), closeTo(bottomInset, 0.1));
      tester.view.physicalSize = const Size(320, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
          find.widgetWithText(AppFormField, "建议歌名"), "窄屏键盘输入");
      await _frames(tester);
      expect(find.text("确认建议").hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text("取消"));
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.physicalSize = const Size(390, 844);
      await _frames(tester);
      await tester.tap(find.byKey(const Key("rename_rule")));
      await _frames(tester);
      await tester.tap(find.text("删除指定字符"));
      await _frames(tester);
      expect(_fieldStyle(tester, "要删除的指定字符"), baseline);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await appDb.close();
    });
  }

  testWidgets("规则面板保留边距和选中反馈，底部复选框全选与清空", (tester) async {
    await _openPlaylist(tester);
    await _playlistMenu(tester, "批量重命名");
    final first = find.byKey(const ValueKey("rename_track_a"));
    final second = find.byKey(const ValueKey("rename_track_b"));
    final box = find.descendant(of: first, matching: find.byType(Checkbox));
    final toggleAll = find.byKey(const Key("rename_toggle_all"));
    // 默认清除开头数字：a/b 命中自动勾选，c 未命中，复选框呈部分选中态
    expect(tester.widget<AppCheckboxRow>(first).value, isTrue);
    expect(tester.widget<AppCheckboxRow>(second).value, isTrue);
    expect(tester.widget<Checkbox>(toggleAll).value, isNull);
    // 未全选时点击 → 全选（含未变更的 c）
    await tester.tap(toggleAll);
    await tester.pump();
    expect(tester.widget<Checkbox>(toggleAll).value, isTrue);
    expect(find.text("已选 3 首"), findsOneWidget);
    // 已全选时点击 → 清空
    await tester.tap(toggleAll);
    await tester.pump();
    expect(tester.widget<Checkbox>(toggleAll).value, isFalse);
    expect(find.text("已选 0 首"), findsOneWidget);
    // 行内方框独立勾选
    await tester.tap(box);
    await tester.pump();
    expect(tester.widget<AppCheckboxRow>(first).value, isTrue);
    expect(find.text("已选 1 首"), findsOneWidget);
    await tester.tap(box);
    await tester.pump();
    expect(tester.widget<AppCheckboxRow>(first).value, isFalse);
    await tester.tap(find.byKey(const Key("rename_rule")));
    await _frames(tester);
    final panel = find.byKey(const Key("app_sheet_panel"));
    final decoration =
        find.descendant(of: panel, matching: find.byType(DecoratedBox)).first;
    final rect = tester.getRect(decoration);
    expect(rect.left, greaterThanOrEqualTo(16));
    expect(rect.right, lessThanOrEqualTo(374));
    expect(rect.bottom, lessThanOrEqualTo(808));
    // 选中瓦片主题色浅底高亮（不再用对勾图标），未选中为浅灰填充；奇数项最后一行通栏
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    // 页面背景的规则字段值与瓦片同名，取弹层内第一个匹配
    final tokens =
        AuroraTokens.of(tester.element(find.text("清除开头数字").first));
    expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey("sheet_action_清除开头数字")))
            .child,
        isA<Container>().having((c) => c.decoration, "decoration",
            isA<BoxDecoration>().having((d) => d.color, "color",
                tokens.primary.withValues(alpha: 0.12))));
    expect(
        tester.widget<InkWell>(
                find.byKey(const ValueKey("sheet_action_清除特殊字符")))
            .child,
        isA<Container>().having((c) => c.decoration, "decoration",
            isA<BoxDecoration>().having(
                (d) => d.color, "color", tokens.tileBg)));
    final lastTile = tester.getRect(
        find.byKey(const ValueKey("sheet_action_删除指定字符")));
    // 面板 1px 描边 + 网格 22 内边距
    expect(lastTile.left, closeTo(rect.left + 23, 0.5));
    expect(lastTile.right, closeTo(rect.right - 23, 0.5));
    // 规则切换立即刷新预览并重置勾选：清除特殊字符对 a/b 重新命中
    await tester.tap(find.text("清除特殊字符"));
    await _frames(tester);
    expect(tester.widget<AppCheckboxRow>(first).value, isTrue);
    expect(tester.widget<AppCheckboxRow>(second).value, isTrue);
    await tester.tap(find.byKey(const Key("rename_apply")));
    await _frames(tester);
    expect((await TrackRepository().getById("a"))!.effectiveName, "01周杰伦晴天");
    expect(
        (await TrackRepository().getById("b"))!.effectiveName, "02周杰伦手写的从前");
    expect((await TrackRepository().getById("c"))!.displayName, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });

  testWidgets("无播放条时操作栏贴近安全区，播放条出现后仍不遮挡操作栏", (tester) async {
    await _openPlaylist(tester);
    await _playlistMenu(tester, "批量重命名");
    final apply = find.byKey(const Key("rename_apply"));
    expect(844 - tester.getRect(apply).bottom, closeTo(40, 0.1));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BatchRenamePage)));
    final track = (await TrackRepository().getById("a"))!;
    container.read(playbackProvider.notifier).play(track);
    await _frames(tester);
    expect(find.byKey(const Key("mini_player")), findsOneWidget);
    expect(tester.getRect(apply).bottom,
        lessThan(tester.getRect(find.byKey(const Key("mini_player"))).top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await appDb.close();
  });
}
