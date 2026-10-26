import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";

import "../../app/design_system_demo.dart";
import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_loading.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/app_palette.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/theme/theme_mode_provider.dart";
import "../../core/theme/theme_providers.dart";
import "../../core/widgets/glass_card.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/theme_swatch.dart";
import "../player/playback_provider.dart";
import "../player/range_proxy_source.dart";
import "../player/sleep_timer_sheet.dart";
import "doc_page.dart";
import "info_pages.dart";
import "settings_info.dart";
import "update_checker.dart";

/// 设置页（对齐原型 renderSetting）：主题真实驱动 + 关于组 + Gallery 隐藏入口
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
                subtitle: "当前版本 $version",
                trailing: Icon(Icons.chevron_right, size: 20, color: t.fgMute),
                onTap: () => _checkUpdate(context, ref),
                // Gallery 隐藏入口（S1.5）：长按版本行进入组件演示页
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DesignSystemDemo()),
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

  /// 检查 GitHub Releases（D5：按版本号比较，避免旧 tag 误判为更新）
  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    AppLoading.show(msg: "检查更新…");
    try {
      final version = await ref.read(appVersionProvider.future);
      final result = await updateChecker.check(version.split("+").first);
      if (!context.mounted) return;
      if (!result.hasUpdate || result.latest == null) {
        AppToast.show(context, "已是最新版本 $version");
        return;
      }
      final latest = result.latest!;
      final go = await AppDialog.show<bool>(
        context,
        title: "发现新版本 ${latest.version}",
        content: SizedBox(
          height: 200,
          child: SingleChildScrollView(
            child: Text(
              latest.notes.trim().isEmpty ? "前往 GitHub 查看更新内容" : latest.notes,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("稍后"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("去下载"),
          ),
        ],
      );
      if (go == true && latest.url.isNotEmpty) {
        final ok = await launchUrl(
          Uri.parse(latest.url),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) AppToast.show(context, "无法打开下载页面");
      }
    } catch (e) {
      print("检查更新失败：$e");
      if (context.mounted) AppToast.show(context, "检查更新失败，请检查网络");
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
