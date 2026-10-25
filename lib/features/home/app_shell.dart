import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_background.dart";
import "../player/mini_player_bar.dart";
import "../playlist/playlist_page.dart";
import "../plaza/plaza_page.dart";
import "../settings/settings_page.dart";
import "home_tab.dart";

/// 应用壳：极光背景 + IndexedStack 三 Tab 保活 + 迷你播放条 + 底部玻璃 Dock
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabControllerProvider);

    return Scaffold(
      // extendBody：内容延伸到 Dock 之下，Dock 自带渐隐+模糊
      extendBody: true,
      body: AuroraBackground(
        // SafeArea：标题不贴状态栏/挖孔（bottom 交给 Dock 的渐隐背景处理）
        child: SafeArea(
          top: true,
          bottom: false,
          child: Stack(
            children: [
              IndexedStack(
                index: tab.index,
                children: const [
                  PlaylistPage(),
                  PlazaPage(),
                  SettingsPage(),
                ],
              ),
              // 迷你播放条悬浮于 Dock 上方（无播放时自隐藏）
              Positioned(
                left: 14,
                right: 14,
                bottom: 74,
                child: const MiniPlayerBar(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const _TabDock(),
    );
  }
}

/// 底部 Dock（原型 .tabbar：74 高，背景向上渐隐 + blur(8)，活动项顶部指示条）
class _TabDock extends ConsumerWidget {
  const _TabDock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final current = ref.watch(homeTabControllerProvider);

    return ClipRect(
      // 渐隐背景：透明 → 页面底色（原型 linear-gradient(180deg, transparent, var(--bg) 60%)）
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.6, 1],
              colors: [
                t.bg.withValues(alpha: 0),
                t.bg.withValues(alpha: 0.85),
                t.bg,
              ],
            ),
          ),
          height: 74,
          padding: const EdgeInsets.only(bottom: 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final (label, icon, tab) in const [
                ("歌单", Icons.library_music_outlined, HomeTab.playlists),
                ("广场", Icons.explore_outlined, HomeTab.plaza),
                ("设置", Icons.settings_outlined, HomeTab.settings),
              ])
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref.read(homeTabControllerProvider.notifier).select(tab),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 活动指示条（原型 .tab.on .ic::before）
                        Container(
                          width: 22,
                          height: 3,
                          margin: const EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: current == tab ? t.primary : Colors.transparent,
                          ),
                        ),
                        Icon(
                          icon,
                          size: 22,
                          color: current == tab ? t.primary : t.fgMute,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: current == tab ? t.primary : t.fgMute,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
