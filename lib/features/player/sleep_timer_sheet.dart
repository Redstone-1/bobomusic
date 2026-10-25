import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

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

/// 定时关闭选择面板（设置页与播放卡更多菜单共用）
void showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(playbackProvider);
  final active = state.sleepDeadline != null || state.stopAfterTrack;

  AppSheet.show(
    context,
    title: "定时关闭",
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
