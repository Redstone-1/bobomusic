import "package:flutter_riverpod/flutter_riverpod.dart";

class DesktopDestination {
  const DesktopDestination(this.route, this.title,
      {this.playlistId, this.canGoBack = false});
  final String route;
  final String title;
  final String? playlistId;
  final bool canGoBack;
  String get key => playlistId == null ? route : "$route:$playlistId";
}

/// 页面仅发出导航意图；应用组合根负责将目的地映射为界面，特性之间不互调页面。
class DesktopNavigation extends Notifier<DesktopDestination> {
  final _history = <DesktopDestination>[];
  @override
  DesktopDestination build() => const DesktopDestination("library", "我的歌单");

  void open(DesktopDestination destination) {
    if (destination.key == state.key) return;
    _history.add(state);
    state = DesktopDestination(destination.route, destination.title,
        playlistId: destination.playlistId, canGoBack: true);
  }

  void back() {
    if (_history.isNotEmpty) state = _history.removeLast();
  }
}

final desktopNavigationProvider =
    NotifierProvider<DesktopNavigation, DesktopDestination>(
        DesktopNavigation.new);

class DesktopSearchRequest {
  const DesktopSearchRequest(this.query, this.sequence);
  final String query;
  final int sequence;
}

/// 顶部搜索框和原有搜索页面共享一次明确提交；同词再次回车仍是一次新请求。
class DesktopSearch extends Notifier<DesktopSearchRequest?> {
  int _sequence = 0;
  @override
  DesktopSearchRequest? build() => null;
  void submit(String query) =>
      state = DesktopSearchRequest(query.trim(), ++_sequence);
}

final desktopSearchProvider =
    NotifierProvider<DesktopSearch, DesktopSearchRequest?>(DesktopSearch.new);
