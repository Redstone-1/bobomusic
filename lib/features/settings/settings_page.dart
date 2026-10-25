import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app/design_system_demo.dart";
import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/theme/theme_mode_provider.dart";
import "../../core/theme/theme_providers.dart";
import "../../core/widgets/glass_card.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/theme_swatch.dart";

/// 设置页（对齐原型 renderSetting）：主题真实驱动 + 关于组 + Gallery 隐藏入口
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final mode = ref.watch(appThemeModeProvider);
    final seed = ref.watch(appThemeSeedProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
      children: [
        const PageHeader(title: "设置", subtitle: "主题 · 外观 · 关于"),
        const SizedBox(height: 16),
        // —— 主题组 ——
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              _SettingRow(
                icon: mode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                title: "主题模式",
                subtitle: "主题色驱动 · 明暗自动生成",
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: _ThemeSeg(
                  current: mode,
                  onSelect: (m) => ref.read(appThemeModeProvider.notifier).set(m),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("主题色", style: TextStyle(fontSize: 12, color: t.fgDim)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in AppThemeColor.values)
                          ThemeSwatch(
                            color: c,
                            selected: c == seed,
                            onTap: () =>
                                ref.read(appThemeSeedProvider.notifier).select(c),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // —— 关于组 ——
        GlassCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              _SettingRow(
                icon: Icons.update_outlined,
                title: "检查更新",
                subtitle: "当前版本 3.0.0",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () {},
                // Gallery 隐藏入口（S1.5）：长按版本行进入组件演示页
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DesignSystemDemo()),
                ),
              ),
              _SettingRow(
                icon: Icons.timer_outlined,
                title: "定时关闭",
                subtitle: "未开启",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // —— 帮助组 ——
        GlassCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              _SettingRow(
                icon: Icons.help_outline,
                title: "帮助",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () {},
              ),
              _SettingRow(
                icon: Icons.description_outlined,
                title: "声明",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () {},
              ),
              _SettingRow(
                icon: Icons.volunteer_activism_outlined,
                title: "鸣谢",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () {},
              ),
            ],
          ),
        ),
        SizedBox(height: t.radiusLg),
      ],
    );
  }
}

/// 设置行（原型 .setrow：图标盒 + 标题/副题 + 尾部）
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(t.radiusMd),
      splashColor: t.surface2,
      highlightColor: t.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: t.surface2,
              ),
              child: Icon(icon, size: 18, color: t.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.fg),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: t.fgDim),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 明暗分段选择（原型 .seg：surface-2 槽 + primary 活动块）
class _ThemeSeg extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onSelect;

  const _ThemeSeg({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: t.surface2,
      ),
      child: Row(
        children: [
          for (final (label, mode) in const [("浅色", ThemeMode.light), ("深色", ThemeMode.dark)])
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: current == mode ? t.primary : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: current == mode ? t.primaryInk : t.fgDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
