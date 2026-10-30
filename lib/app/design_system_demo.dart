import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/overlays/app_dialog.dart";
import "../core/overlays/app_loading.dart";
import "../core/overlays/app_sheet.dart";
import "../core/overlays/app_toast.dart";
import "../core/theme/app_palette.dart";
import "../core/theme/theme_mode_provider.dart";
import "../core/theme/theme_providers.dart";
import "../core/widgets/app_buttons.dart";
import "../core/widgets/aurora_background.dart";
import "../core/widgets/aurora_progress_bar.dart";
import "../core/widgets/empty_state.dart";
import "../core/widgets/glass_card.dart";
import "../core/widgets/song_list_tile.dart";
import "../core/widgets/skeleton.dart";
import "../core/widgets/theme_swatch.dart";
import "../data/models/track.dart";

/// S1.2/S1.3 设计系统验证页（S1.4 移除）：明暗 × 10 主题色实时切换 + 全部组件陈列
class DesignSystemDemo extends ConsumerStatefulWidget {
  const DesignSystemDemo({super.key});

  @override
  ConsumerState<DesignSystemDemo> createState() => _DesignSystemDemoState();
}

class _DesignSystemDemoState extends ConsumerState<DesignSystemDemo> {
  // 极光动画开关：对比性能用（合成器位移应为零重绘）
  bool _auroraAnimated = true;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appThemeModeProvider);
    final seed = ref.watch(appThemeSeedProvider);

    return Scaffold(
      body: AuroraBackground(
        animated: _auroraAnimated,
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
                          "S1.3 · 全局组件",
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
              const SizedBox(height: 10),
              Row(
                children: [
                  GlassChip(
                    label: _auroraAnimated ? "极光动画：开" : "极光动画：关",
                    onTap: () => setState(() => _auroraAnimated = !_auroraAnimated),
                  ),
                  const SizedBox(width: 9),
                  const Text("卡顿对比开关", style: TextStyle(fontSize: 11)),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle("主题色 · ${AppThemeColor.values.length} 色"),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in AppThemeColor.values)
                    ThemeSwatch(
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
                  GlassChip(label: "已选中", selected: true),
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
              const _SectionTitle("Toast / 加载态"),
              Row(
                children: [
                  GlassChip(
                    label: "弹 Toast",
                    onTap: () => AppToast.show(context, "已加入播放队列"),
                  ),
                  const SizedBox(width: 9),
                  GlassChip(
                    label: "加载 2 秒",
                    onTap: () {
                      AppLoading.show(msg: "正在加载…");
                      Future.delayed(const Duration(seconds: 2), AppLoading.dismiss);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle("弹窗"),
              Row(
                children: [
                  GlassChip(
                    label: "确认弹窗",
                    onTap: () async {
                      final ok = await AppDialog.confirm(
                        context,
                        title: "删除歌单",
                        message: "歌单「雨天钢琴」将被删除，歌曲不受影响。",
                        danger: true,
                        confirmText: "删除",
                      );
                      if (context.mounted) {
                        AppToast.show(context, ok ? "已删除" : "已取消");
                      }
                    },
                  ),
                  const SizedBox(width: 9),
                  GlassChip(
                    label: "输入弹窗",
                    onTap: () async {
                      final name = await AppDialog.input(
                        context,
                        title: "新建歌单",
                        hint: "歌单名（1~20 字）",
                      );
                      if (context.mounted && name != null) {
                        AppToast.show(context, "已创建「$name」");
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle("底部操作面板（长按菜单同款）"),
              Row(
                children: [
                  GlassChip(
                    label: "歌曲操作",
                    onTap: () => AppSheet.show(
                      context,
                      title: "夜航西飞",
                      actions: [
                        AppSheetAction(
                          icon: Icons.queue_music_outlined,
                          label: "下一首播放",
                          onTap: () {},
                        ),
                        AppSheetAction(
                          icon: Icons.playlist_add,
                          label: "加入歌单",
                          onTap: () {},
                        ),
                        AppSheetAction(
                          icon: Icons.download_outlined,
                          label: "下载",
                          onTap: () {},
                        ),
                        AppSheetAction(
                          icon: Icons.delete_outline,
                          label: "从歌单删除",
                          danger: true,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle("进度条 · 静态 / 可拖动"),
              const AuroraProgressBar(value: 0.38),
              const SizedBox(height: 20),
              const _InteractiveProgress(),
              const SizedBox(height: 22),
              const _SectionTitle("空状态 · 整页规格"),
              // 演示卡包有界高度：空状态在有界容器内撑满居中（列表场景自动取半屏）
              const GlassCard(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  height: 200,
                  child: EmptyState(
                    asset: "assets/illustrations/empty_music.svg",
                    title: "还没有本地音乐",
                    subtitle: "点击右上角 + 扫描手机里的音频文件",
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle("分区空态 · 紧凑版（歌单页/广场页内嵌）"),
              GlassCard(
                padding: const EdgeInsets.all(8),
                child: const SizedBox(
                  height: 190,
                  child: EmptyState(
                    compact: true,
                    asset: "assets/illustrations/empty_collection.svg",
                    title: "还没有歌单",
                    subtitle: "点右上角 + 创建第一个歌单",
                  ),
                ),
              ),
              const Divider(height: 1),
              GlassCard(
                padding: const EdgeInsets.all(8),
                child: const SizedBox(
                  height: 190,
                  child: EmptyState(
                    compact: true,
                    asset: "assets/illustrations/empty_music.svg",
                    title: "还没有播放记录",
                    subtitle: "播放的歌曲会出现在这里",
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle("加载占位 · 分区骨架（异步 loading 态）"),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SkeletonListView(rows: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 陈列数据 ----

const _demoTracks = [
  Track(
    id: "demo-1",
    name: "夜航西飞",
    author: "陈鸿宇",
    duration: 252,
  ),
  Track(
    id: "demo-2",
    name: "漠河舞厅",
    author: "柳爽",
    duration: 311,
    origin: OriginType.kuwo,
  ),
  Track(
    id: "demo-3",
    name: "本地录音demo",
    author: "未知歌手",
    duration: 198,
    origin: OriginType.local,
  ),
];

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

/// 主题色选点已提升为共享组件：core/widgets/theme_swatch.dart

/// 可拖动进度条演示（模拟 seek）
class _InteractiveProgress extends StatefulWidget {
  const _InteractiveProgress();

  @override
  State<_InteractiveProgress> createState() => _InteractiveProgressState();
}

class _InteractiveProgressState extends State<_InteractiveProgress> {
  var _value = 0.5;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text("${(_value * 100).toStringAsFixed(0)}%"),
        const SizedBox(height: 8),
        AuroraProgressBar(
          value: _value,
          onChanged: (v) => setState(() => _value = v),
        ),
      ],
    );
  }
}
