import "package:riverpod_annotation/riverpod_annotation.dart";

part "home_tab.g.dart";

/// 底部 Dock 的三个主 Tab
enum HomeTab { playlists, plaza, settings }

/// 当前所在 Tab（IndexedStack 保活各页滚动位置）
@riverpod
class HomeTabController extends _$HomeTabController {
  @override
  HomeTab build() => HomeTab.playlists;

  void select(HomeTab tab) => state = tab;
}
