import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app/design_system_demo.dart";
import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_loading.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/theme/theme_mode_provider.dart";
import "../../core/theme/theme_providers.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/glass_card.dart";
import "../../core/widgets/icon_box.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/theme_swatch.dart";
import "../download/downloads_page.dart";
import "../player/playback_provider.dart";
import "../player/range_proxy_source.dart";
import "../player/sleep_timer_sheet.dart";
import "doc_page.dart";
import "info_pages.dart";
import "settings_info.dart";
import "update_checker.dart";
import "update_prompt.dart";

/// 设置页：主题偏好、应用管理与说明入口。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final mode = ref.watch(appThemeModeProvider);
    final seed = ref.watch(appThemeSeedProvider);
    // 只订阅定时关闭文案（不订阅 position，避免设置页每秒重建）
    final sleepLabel = ref.watch(playbackProvider.select(sleepTimerLabel));
    final version = ref.watch(appVersionProvider).value ?? "3.0.0";
    final cacheSize = ref.watch(audioCacheSizeProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(DesktopContent.of(context) ? 30 : 20, DesktopContent.of(context) ? 30 : 16, DesktopContent.of(context) ? 30 : 20, DesktopContent.of(context) ? 30 : 150),
      children: [
        PageHeader(
          title: "设置",
          subtitle: "主题 · 外观 · 关于",
          trailing: Tooltip(
            message: mode == ThemeMode.dark ? "切换为浅色" : "切换为深色",
            child: Semantics(
              button: true,
              child: GlassIconButton(
                size: 44,
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                onTap: () => ref.read(appThemeModeProvider.notifier).toggle(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // —— 主题组 ——
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SettingRow(
                icon: Icons.palette_outlined,
                title: "主题色",
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(
                  spacing: 12,
                  children: [
                    // 每行五色并均分剩余宽度，让两行圆点上下对齐、两端铺满。
                    for (var start = 0;
                        start < AppThemeColor.values.length;
                        start += 5)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final c
                              in AppThemeColor.values.skip(start).take(5))
                            ThemeSwatch(
                              color: c,
                              selected: c == seed,
                              onTap: () => ref
                                  .read(appThemeSeedProvider.notifier)
                                  .select(c),
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
                icon: Icons.download_outlined,
                title: "下载管理",
                subtitle: "已下载与下载中的任务",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DownloadsPage()),
                ),
              ),
              _SettingRow(
                icon: Icons.timer_outlined,
                title: "定时关闭",
                subtitle: sleepLabel,
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => showSleepTimerSheet(context, ref),
              ),
              _SettingRow(
                icon: Icons.cleaning_services_outlined,
                title: "清理音频缓存",
                subtitle: cacheSize.when(
                  data: formatBytes,
                  loading: () => "计算中…",
                  error: (_, __) => "未知",
                ),
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => _clearCache(context, ref),
              ),
              _SettingRow(
                icon: Icons.update_outlined,
                title: "检查更新",
                subtitle: "当前版本 $version",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => _checkUpdate(context, ref),
                // Gallery 隐藏入口（S1.5）：长按版本行进入组件演示页
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DesignSystemDemo()),
                ),
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
                onTap: () =>
                    _openDoc(context, "使用帮助", "assets/markdown/help_doc.md"),
              ),
              _SettingRow(
                icon: Icons.description_outlined,
                title: "声明",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeclarationPage()),
                ),
              ),
              _SettingRow(
                icon: Icons.volunteer_activism_outlined,
                title: "鸣谢",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThanksPage()),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: t.radiusLg),
      ],
    );
  }

  /// 检查更新（D5：按版本号比较，避免旧 tag 误判为更新）
  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    AppLoading.show(msg: "检查更新…");
    try {
      final version = await ref.read(appVersionProvider.future);
      final result = await updateChecker.check(version);
      if (!context.mounted) return;
      if (!result.hasUpdate || result.latest == null) {
        AppToast.show(context, "已是最新版本 $version");
        return;
      }
      final latest = result.latest!;
      await showUpdateFoundDialog(context, latest);
    } catch (e) {
      print("检查更新失败：$e");
      if (context.mounted) AppToast.show(context, "检查更新失败，请稍后再试");
    } finally {
      AppLoading.dismiss();
    }
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final ok = await AppDialog.confirm(
      context,
      title: "清理音频缓存",
      message: "将删除边听边缓存的音频文件；已下载歌曲与歌单不受影响。",
      confirmText: "清理",
    );
    if (ok != true || !context.mounted) return;
    final freed = await RangeProxySource.clearAudioCache();
    ref.invalidate(audioCacheSizeProvider);
    if (context.mounted) AppToast.show(context, "已释放 ${formatBytes(freed)}");
  }

  void _openDoc(BuildContext context, String title, String asset) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocPage(title: title, asset: asset)),
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
            IconBox(icon: icon),
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
