import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/theme/app_palette.dart";
import "../core/theme/theme_mode_provider.dart";
import "../core/theme/theme_providers.dart";
import "../core/widgets/app_buttons.dart";
import "../core/widgets/aurora_background.dart";
import "../core/widgets/empty_state.dart";
import "../core/widgets/glass_card.dart";
import "../core/widgets/song_list_tile.dart";
import "../data/models/track.dart";

/// 应用根 Widget：装配主题与全局壳
/// S1.4 起由三 Tab 导航壳接管 home；当前 home 为设计系统验证页
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final light = ref.watch(appLightThemeProvider);
    final dark = ref.watch(appDarkThemeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      home: const _DesignSystemDemo(),
    );
  }
}

// ---- S1.2 设计系统验证页（S1.4 移除）：明暗 × 8 主题色实时切换 + 组件陈列 ----

const _demoTracks = [
  Track(
    id: "demo-1",
    name: "夜航西飞",
    author: "陈鸿宇",
    duration: 252,
    coverHue: 212,
  ),
  Track(
    id: "demo-2",
    name: "漠河舞厅",
    author: "柳爽",
    duration: 311,
    origin: OriginType.kuwo,
    coverHue: 8,
  ),
  Track(
    id: "demo-3",
    name: "本地录音demo",
    author: "未知歌手",
    duration: 198,
    origin: OriginType.local,
    coverHue: 46,
  ),
];

class _DesignSystemDemo extends ConsumerWidget {
  const _DesignSystemDemo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final seed = ref.watch(appThemeSeedProvider);

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "S1.2 · 设计系统",
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text("风格 A · 沉浸极光玻璃"),
                      ],
                    ),
                  ),
                  GlassIconButton(
                    icon: Icon(
                      mode == ThemeMode.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    onTap: () =>
                        ref.read(appThemeModeProvider.notifier).toggle(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _SectionTitle("主题色 · 8 色"),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in AppThemeColor.values)
                    _SeedSwatch(
                      key: ValueKey("seed_${c.name}"),
                      color: c,
                      selected: c == seed,
                      onTap: () =>
                          ref.read(appThemeSeedProvider.notifier).select(c),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle("玻璃卡片"),
              const GlassCard(
                padding: EdgeInsets.all(16),
                child: Text("普通玻璃卡片 · surface + 发丝描边"),
              ),
              const SizedBox(height: 12),
              const GlassCard(
                frosted: true,
                padding: EdgeInsets.all(16),
                child: Text("磨砂玻璃卡片 · blur + saturate（叠在极光上看效果）"),
              ),
              const SizedBox(height: 22),
              const _SectionTitle("按钮"),
              Row(
                children: [
                  PrimaryIconButton(
                    icon: const Icon(Icons.play_arrow),
                    onTap: () {},
                  ),
                  const SizedBox(width: 18),
                  GlassIconButton(
                    icon: const Icon(Icons.search),
                    onTap: () {},
                  ),
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: const Icon(Icons.more_vert),
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  GlassChip(label: "播放全部", selected: true),
                  SizedBox(width: 9),
                  GlassChip(label: "加入待播放"),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle("歌曲行 · 含音源标签 / 播放高亮"),
              SongListTile(track: _demoTracks[0], playing: true, onTap: () {}),
              SongListTile(track: _demoTracks[1], onTap: () {}),
              SongListTile(track: _demoTracks[2], onTap: () {}),
              const SizedBox(height: 22),
              const _SectionTitle("空状态"),
              const GlassCard(
                padding: EdgeInsets.all(16),
                child: EmptyState(
                  emoji: "🎵",
                  title: "还没有本地音乐",
                  subtitle: "点击右上角 + 扫描手机里的音频文件",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 主题色选点（原型 .sw：选中描边 + ✓）
class _SeedSwatch extends StatelessWidget {
  final AppThemeColor color;
  final bool selected;
  final VoidCallback onTap;

  const _SeedSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.color,
          border: Border.all(
            width: 2,
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: selected
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : null,
      ),
    );
  }
}
