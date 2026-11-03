import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/navigation/desktop_navigation.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/theme/theme_mode_provider.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/empty_state.dart";
import "../../data/models/playlist.dart";
import "../../features/download/downloads_page.dart";
import "../../features/player/desktop_player.dart";
import "../../features/player/queue_sheet.dart";
import "../../core/window/windows_window.dart";
import "../../features/player/playback_provider.dart";
import "../../features/playlist/playlist_commands.dart";
import "../../features/playlist/playlist_detail_page.dart";
import "../../features/playlist/playlist_page.dart";
import "../../features/playlist/playlists_provider.dart";
import "../../features/playlist/recent_tracks_page.dart";
import "../../features/plaza/plaza_page.dart";
import "../../features/plaza/hot_songs_provider.dart";
import "../../features/plaza/search_page.dart";
import "../../features/settings/settings_page.dart";

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});
  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _navigator = GlobalKey<NavigatorState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _visited = <String, DesktopDestination>{};
  late final _observer = _DesktopRouteObserver(() {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    windowsWindowController?.beforeClose = () async {
      try {
        await ref.read(playbackProvider.notifier).prepareForExit();
      } catch (error) {
        if (mounted) AppToast.show(context, "退出前保存失败：$error");
        rethrow;
      }
    };
  }

  @override
  void dispose() {
    windowsWindowController?.beforeClose = null;
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _open(DesktopDestination destination) {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    ref.read(desktopNavigationProvider.notifier).open(destination);
  }

  void _submit(String query) {
    _open(const DesktopDestination("search", "搜索音乐"));
    ref.read(desktopSearchProvider.notifier).submit(query);
  }

  void _back() {
    if (_navigator.currentState?.canPop() == true) {
      _navigator.currentState!.pop();
    } else {
      ref.read(desktopNavigationProvider.notifier).back();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final commands = ref.read(playbackProvider.notifier);
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (keyboard.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        commands.next();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        commands.previous();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      commands.toggle();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      if (ref.read(desktopNavigationProvider).route == "player") {
        _back();
      } else {
        _open(const DesktopDestination("player", "正在播放"));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ &&
        _navigator.currentContext != null) {
      showPlaybackQueueSheet(_navigator.currentContext!);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        ref.read(desktopNavigationProvider).route == "player") {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _page(DesktopDestination destination) => switch (destination.route) {
        "library" => const PlaylistPage(),
        "plaza" => const PlazaPage(),
        "local" => const PlaylistDetailPage(
            playlist: Playlist(
                id: "builtin:local", name: "本地音乐", type: PlaylistType.builtIn)),
        "liked" => const PlaylistDetailPage(playlist: kBuiltinLikedPlaylist),
        "recent" => const RecentTracksPage(),
        "downloads" => const DownloadsPage(),
        "settings" => const SettingsPage(),
        "search" => const SearchPage(),
        "player" => const DesktopPlayerPage(),
        "playlist" => PlaylistDetailPage(
            playlist: Playlist(
                id: destination.playlistId!,
                name: destination.title,
                type: PlaylistType.custom)),
        _ => const EmptyState(title: "请选择音乐", subtitle: "从音乐库或广场开始聆听"),
      };

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final selected = ref.watch(desktopNavigationProvider);
    _visited[selected.key] = selected;
    ref.listen(desktopNavigationProvider, (_, next) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    });
    ref.listen(playbackProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      AppToast.show(context, "播放失败：$error");
      ref.read(playbackProvider.notifier).clearError();
    });
    // 与手机壳共用播放期探测结果，桌面播放试听片段时也给出原因。
    ref.listen(vipLimitedTrackIdsProvider, (previous, next) {
      if (next.length > (previous?.length ?? 0)) {
        AppToast.show(context, "该歌曲需要酷我 VIP，仅提供试听片段");
      }
    });
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            _open(const DesktopDestination("search", "搜索音乐"));
            _searchFocus.requestFocus();
          },
        },
        child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Scaffold(
              body: AuroraBackground(
                  desktop: true,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final compact = constraints.maxWidth <= 820;
                    final showRight = constraints.maxWidth > 1090 &&
                        selected.route != "player";
                    return Column(children: [
                      Expanded(
                          child: Row(children: [
                        SizedBox(
                            width: compact ? 74 : 212,
                            child: _sidebar(t, selected, compact)),
                        Expanded(
                            child: Column(children: [
                          _topbar(t, selected),
                          Expanded(
                              child: Row(children: [
                            Expanded(
                                child: DesktopContent(
                                    child: Theme(
                              data: Theme.of(context).copyWith(
                                  scaffoldBackgroundColor:
                                      t.bg.withValues(alpha: 0)),
                              child: Navigator(
                                  key: _navigator,
                                  observers: [_observer],
                                  onGenerateRoute: (_) => MaterialPageRoute(
                                      builder: (_) => Consumer(
                                              builder: (context, ref, child) {
                                            final active = ref.watch(
                                                desktopNavigationProvider);
                                            final destinations =
                                                _visited.values.toList();
                                            return IndexedStack(
                                                index: destinations.indexWhere(
                                                    (item) =>
                                                        item.key == active.key),
                                                children: [
                                                  for (final destination
                                                      in destinations)
                                                    KeyedSubtree(
                                                        key: ValueKey(
                                                            destination.key),
                                                        child: TickerMode(
                                                          enabled:
                                                              destination.key ==
                                                                  active.key,
                                                          child: ExcludeFocus(
                                                            excluding:
                                                                destination
                                                                        .key !=
                                                                    active.key,
                                                            child: _page(
                                                                destination),
                                                          ),
                                                        )),
                                                ]);
                                          }))),
                            ))),
                            if (showRight)
                              SizedBox(
                                  width: 296,
                                  child: const DesktopNowPlayingPanel()),
                          ])),
                        ])),
                      ])),
                      const DesktopPlayerBar(),
                    ]);
                  })),
            )));
  }

  Widget _sidebar(AuroraTokens t, DesktopDestination selected, bool compact) {
    final playlists = ref.watch(playlistsProvider);
    return Container(
        decoration: BoxDecoration(
            color: t.surface,
            border: Border(right: BorderSide(color: t.hairline))),
        child: Column(children: [
          Padding(
              padding: EdgeInsets.fromLTRB(compact ? 14 : 24, 26, 14, 30),
              child: Row(children: [
                Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: t.primary,
                        borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.headphones, color: t.primaryInk)),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("啵啵音乐",
                            style: TextStyle(
                                color: t.fg,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                        Text("听歌自由",
                            style: TextStyle(
                                color: t.fgMute,
                                fontSize: 10,
                                letterSpacing: 2))
                      ])
                ],
              ])),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                if (!compact) _navLabel(t, "探索与收藏"),
                for (final entry in const [
                  ("library", "我的歌单", Icons.library_music_outlined),
                  ("plaza", "音乐广场", Icons.explore_outlined)
                ])
                  _navItem(t, selected, compact,
                      DesktopDestination(entry.$1, entry.$2), entry.$3),
                const SizedBox(height: 20),
                if (!compact) _navLabel(t, "我的音乐"),
                for (final entry in const [
                  ("local", "本地音乐", Icons.headphones_outlined),
                  ("liked", "我喜欢", Icons.favorite_border),
                  ("recent", "最近播放", Icons.history),
                  ("downloads", "下载管理", Icons.download_outlined)
                ])
                  _navItem(t, selected, compact,
                      DesktopDestination(entry.$1, entry.$2), entry.$3),
                if (!compact) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: _navLabel(t, "自定义歌单")),
                    IconButton(
                        tooltip: "新建歌单",
                        onPressed: () => createPlaylist(context, ref),
                        icon: Icon(Icons.add, size: 17, color: t.fgDim))
                  ]),
                  if (playlists.hasError)
                    TextButton(
                        onPressed: () => ref.invalidate(playlistsProvider),
                        child: const Text("歌单加载失败，点击重试")),
                  for (final playlist in playlists.value ?? <Playlist>[])
                    _navItem(
                        t,
                        selected,
                        false,
                        DesktopDestination("playlist", playlist.name,
                            playlistId: playlist.id),
                        Icons.queue_music),
                ],
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
              child: _navItem(
                  t,
                  selected,
                  compact,
                  const DesktopDestination("settings", "设置"),
                  Icons.settings_outlined)),
        ]));
  }

  Widget _navLabel(AuroraTokens t, String label) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 0, 10),
      child: Text(label,
          style: TextStyle(color: t.fgMute, fontSize: 10, letterSpacing: 1.5)));
  Widget _navItem(AuroraTokens t, DesktopDestination selected, bool compact,
      DesktopDestination destination, IconData icon) {
    final active = destination.key == selected.key;
    return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
            message: destination.title,
            child: Material(
                color: active
                    ? t.primary.withValues(alpha: .12)
                    : t.bg.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey("desktop_nav_${destination.key}"),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(destination),
                  child: SizedBox(
                      height: 43,
                      child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 0 : 12),
                          child: Row(
                              mainAxisAlignment: compact
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              children: [
                                Icon(icon,
                                    color: active ? t.primary : t.fgDim,
                                    size: 19),
                                if (!compact) ...[
                                  const SizedBox(width: 11),
                                  Expanded(
                                      child: Text(destination.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color:
                                                  active ? t.primary : t.fgDim,
                                              fontSize: 12,
                                              fontWeight: active
                                                  ? FontWeight.w700
                                                  : FontWeight.w400)))
                                ],
                              ]))),
                ))));
  }

  Widget _topbar(AuroraTokens t, DesktopDestination selected) => Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.hairline))),
      child: Row(children: [
        IconButton(
            tooltip: "返回",
            onPressed: _observer.canPop || selected.canGoBack ? _back : null,
            icon: const Icon(Icons.chevron_left)),
        const SizedBox(width: 12),
        Expanded(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: TextField(
                    key: const Key("desktop_search"),
                    controller: _search,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submit,
                    onChanged: (value) {
                      if (value.trim().isEmpty) {
                        ref.read(desktopSearchProvider.notifier).submit("");
                      }
                    },
                    style: TextStyle(color: t.fg, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: "搜索歌曲 / 歌手 / 合集",
                      hintStyle: TextStyle(color: t.fgMute),
                      prefixIcon: Icon(Icons.search, color: t.fgMute, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: t.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: t.hairline)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: t.hairline)),
                    )))),
        const SizedBox(width: 16),
        IconButton(
            tooltip: "切换明暗主题",
            onPressed: () => ref.read(appThemeModeProvider.notifier).toggle(),
            icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 20)),
      ]));
}

class _DesktopRouteObserver extends NavigatorObserver {
  _DesktopRouteObserver(this.onChanged);
  final VoidCallback onChanged;
  bool canPop = false;
  void _update() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      canPop = navigator?.canPop() ?? false;
      onChanged();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();
}
