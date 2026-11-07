import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "settings_info.dart";
import "update_checker.dart";

/// 启动静默检测总开关（测试默认关：避免 FakeAsync 下挂起 Timer 与真实网络）
bool silentUpdateCheckEnabled = true;

bool _launchCheckScheduled = false;

/// 测试重置调度标志（模块级状态会跨用例残留）
void resetLaunchUpdateCheck() => _launchCheckScheduled = false;

/// 冷启动静默检测一次新版本：壳首帧调用（模块级标志防重），延迟 2s
/// 避开启动恢复的竞速；无更新与失败都保持安静
void scheduleLaunchUpdateCheck(BuildContext context, WidgetRef ref) {
  if (_launchCheckScheduled || !silentUpdateCheckEnabled) return;
  _launchCheckScheduled = true;
  Future.delayed(const Duration(seconds: 2), () {
    if (!context.mounted) return;
    silentCheckForUpdate(context, ref);
  });
}

/// 静默检查：仅在有新版本时弹「发现新版本」，失败只 print 不提示
Future<void> silentCheckForUpdate(BuildContext context, WidgetRef ref) async {
  try {
    final version = await ref.read(appVersionProvider.future);
    final result = await updateChecker.check(version);
    if (!context.mounted || !result.hasUpdate || result.latest == null) return;
    await showUpdateFoundDialog(context, result.latest!);
  } catch (e) {
    print("启动检查更新失败：$e");
  }
}

/// 「发现新版本」弹窗：更新内容自适应高度（字少弹窗矮），封顶 320 滚动；
/// 选「去下载」拉起外部浏览器
Future<void> showUpdateFoundDialog(
  BuildContext context,
  AppRelease release,
) async {
  final go = await AppDialog.show<bool>(
    context,
    title: "发现新版本 ${release.version}",
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Text(
          release.notes.trim().isEmpty ? "前往发布页查看更新内容" : release.notes,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
    ),
    // 按钮遵循全仓对话框约定：取消 fgDim / 确认 primary + w700（AppDialog 同款）
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          "稍后",
          style: TextStyle(color: AuroraTokens.of(context).fgDim),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          "去下载",
          style: TextStyle(
            color: AuroraTokens.of(context).primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
  if (go == true && release.url.isNotEmpty && context.mounted) {
    final ok = await launchUrl(
      Uri.parse(release.url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) AppToast.show(context, "无法打开下载页面");
  }
}
