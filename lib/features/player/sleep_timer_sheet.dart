import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "playback_provider.dart";

/// 定时关闭状态文案（设置页/播放卡共用）
String sleepTimerLabel(PlaybackState state) {
  if (state.stopAfterTrack) return "播完当前曲后停止";
  final deadline = state.sleepDeadline;
  if (deadline == null) return "未开启";
  final remain = deadline.difference(DateTime.now());
  if (remain <= Duration.zero) return "即将停止";
  final minutes = (remain.inSeconds / 60).ceil();
  return "约 $minutes 分钟后停止";
}

/// 播放卡更多菜单项文案（所有者 2026-11-07 定）：未开启只显示「定时关闭」，
/// 已开启直接给状态（如「60 分钟后」「播完当前曲后」），不再包一层括号
String sleepTimerMenuLabel(PlaybackState state) {
  if (state.stopAfterTrack) return "播完当前曲后";
  final deadline = state.sleepDeadline;
  if (deadline == null) return "定时关闭";
  final remain = deadline.difference(DateTime.now());
  if (remain <= Duration.zero) return "即将停止";
  return "${(remain.inSeconds / 60).ceil()} 分钟后";
}

/// 自定义定时时长（分钟）：1~1440（一天内）
Future<void> _setCustomSleepTimer(
  BuildContext context,
  WidgetRef ref,
) async {
  final input = await AppDialog.input(
    context,
    title: "自定义时长",
    hint: "分钟数（1~1440）",
    validator: (value) {
      final minutes = int.tryParse(value?.trim() ?? "");
      if (minutes == null || minutes < 1 || minutes > 1440) {
        return "请输入 1~1440 的整数分钟";
      }
      return null;
    },
  );
  if (input == null || !context.mounted) return;
  final minutes = int.parse(input.trim());
  ref
      .read(playbackProvider.notifier)
      .setSleepAfter(Duration(minutes: minutes));
  if (context.mounted) AppToast.show(context, "$minutes 分钟后停止播放");
}

/// 定时关闭选择面板（设置页与播放卡更多菜单共用）
void showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(playbackProvider);
  final active = state.sleepDeadline != null || state.stopAfterTrack;

  AppSheet.show(
    context,
    actions: [
      for (final (label, minutes) in const [
        ("15 分钟", 15),
        ("30 分钟", 30),
        ("60 分钟", 60),
        ("90 分钟", 90),
      ])
        AppSheetAction(
          icon: Icons.timer_outlined,
          label: label,
          onTap: () {
            ref
                .read(playbackProvider.notifier)
                .setSleepAfter(Duration(minutes: minutes));
            AppToast.show(context, "$label后停止播放");
          },
        ),
      AppSheetAction(
        icon: Icons.edit_outlined,
        label: "自定义",
        onTap: () => _setCustomSleepTimer(context, ref),
      ),
      AppSheetAction(
        icon: Icons.music_note_outlined,
        label: "播完当前曲",
        onTap: () {
          ref.read(playbackProvider.notifier).setStopAfterCurrent();
          AppToast.show(context, "将在当前曲播完后停止");
        },
      ),
      if (active)
        AppSheetAction(
          icon: Icons.timer_off_outlined,
          label: "关闭定时",
          danger: true,
          onTap: () {
            ref.read(playbackProvider.notifier).cancelSleep();
            AppToast.show(context, "已关闭定时关闭");
          },
        ),
    ],
  );
}
