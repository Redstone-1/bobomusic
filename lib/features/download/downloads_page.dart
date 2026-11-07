import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/aurora_progress_bar.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/glass_card.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/skeleton.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/track.dart";
import "../../data/repositories/track_repository.dart";
import "../player/cover_fly_animation.dart";
import "../player/mini_player_bar.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "../playlist/add_to_playlist_sheet.dart";
import "../playlist/track_edit_dialog.dart";
import "download_tasks.dart";

enum _DownloadTab { done, active }

/// 下载管理：已完成（tracks.downloaded_at）+ 下载中（内存任务）
/// 空态走覆盖层（Stack + Positioned.fill 居中于列表可视区，透明区点击穿透），
/// 加载/错误留在列表流内——与歌单详情/搜索页同一套空态规范
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  _DownloadTab _tab = _DownloadTab.done;

  @override
  Widget build(BuildContext context) {
    final doneAsync = ref.watch(downloadedTracksProvider);
    final tasks = ref.watch(downloadTasksProvider);
    final active = [
      for (final task in tasks)
        if (task.status != DownloadTaskStatus.completed) task,
    ];
    final downloading = active.where((task) => task.active).length;
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );
    final playingNow = ref.watch(playbackProvider.select((s) => s.playing));
    // 仅「加载完成且无错且为空」才显示覆盖空态（加载/错误走列表流内）
    final doneEmpty = !doneAsync.isLoading &&
        !doneAsync.hasError &&
        (doneAsync.value?.isEmpty ?? false);

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BackLink(),
                      PageHeader(
                        title: "下载管理",
                        subtitle:
                            "已完成 ${doneAsync.value?.length ?? 0} 首 · 下载中 $downloading 首",
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          GlassChip(
                            label: "已下载 ${doneAsync.value?.length ?? 0}",
                            selected: _tab == _DownloadTab.done,
                            onTap: () =>
                                setState(() => _tab = _DownloadTab.done),
                          ),
                          const SizedBox(width: 10),
                          GlassChip(
                            label: "下载中 ${active.length}",
                            selected: _tab == _DownloadTab.active,
                            onTap: () =>
                                setState(() => _tab = _DownloadTab.active),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                        children: [
                          if (_tab == _DownloadTab.done)
                            _buildDone(doneAsync, currentTrackId, playingNow)
                          else
                            _buildActive(active),
                        ],
                      ),
                      if (_tab == _DownloadTab.done && doneEmpty)
                        // 底部垫高让空态视觉居中于整屏而非剩余区域（所有者反馈偏下）
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 90),
                            child: const EmptyState(
                              asset: "assets/illustrations/empty_download.svg",
                              title: "还没有下载",
                              subtitle: "在歌曲菜单中选择「下载」，离线也能听",
                            ),
                          ),
                        ),
                      if (_tab == _DownloadTab.active && active.isEmpty)
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 90),
                            child: const EmptyState(
                              asset: "assets/illustrations/empty_download.svg",
                              title: "没有正在下载的任务",
                              subtitle: "下载完成后会出现在「已下载」",
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDone(
      AsyncValue<List<Track>> doneAsync, String? currentTrackId, bool playing) {
    return doneAsync.when(
      loading: () => const SkeletonListView(rows: 4),
      error: (e, _) => EmptyState(
        compact: true,
        asset: "assets/illustrations/empty_alert.svg",
        title: "下载列表加载失败",
        subtitle: "点击重试",
        action: GlassChip(
          label: "重试",
          onTap: () => ref.invalidate(downloadedTracksProvider),
        ),
      ),
      // 空数据由覆盖层空态负责，列表流保持空占位
      data: (tracks) => tracks.isEmpty
          ? const SizedBox.shrink()
          : Column(
              children: [
                for (final track in tracks)
                  SongListTile(
                    track: track,
                    playing: track.id == currentTrackId,
                    paused: !playing,
                    onCoverTap: (coverRect) =>
                        addTrackToQueueWithFly(context, ref, track,
                            from: coverRect),
                    onTap: () => PlayerCardPage.start(
                      context,
                      ref,
                      track,
                      queue: tracks,
                    ),
                    onMorePressed: () => _showDoneActions(track),
                  ),
              ],
            ),
    );
  }

  Widget _buildActive(List<DownloadTask> tasks) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final task in tasks) ...[
          _TaskTile(task: task),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  void _showDoneActions(Track track) {
    AppSheet.show(
      context,
      actions: [
        if (Platform.isWindows && track.localPath != null)
          AppSheetAction(
            icon: Icons.folder_open_outlined,
            label: "打开所在文件夹",
            onTap: () async {
              try {
                if (!await launchUrl(
                    Uri.directory(File(track.localPath!).parent.path),
                    mode: LaunchMode.externalApplication)) {
                  throw StateError("无法打开目录");
                }
              } catch (e) {
                if (mounted) AppToast.show(context, "打开文件夹失败：$e");
              }
            },
          ),
        AppSheetAction(
          icon: Icons.edit_outlined,
          label: "编辑信息",
          onTap: () => showTrackEditDialog(context, ref, track),
        ),
        AppSheetAction(
          icon: Icons.library_add_outlined,
          label: "加入歌单",
          onTap: () => showAddToPlaylistSheet(context, ref, [track]),
        ),
        AppSheetAction(
          icon: Icons.delete_outline,
          label: "删除下载",
          danger: true,
          onTap: () => _deleteDownload(track),
        ),
      ],
    );
  }

  Future<void> _deleteDownload(Track track) async {
    final ok = await AppDialog.confirm(
      context,
      title: "删除下载",
      message: "将删除本地文件并移除离线标记，歌单中的引用不受影响。",
      confirmText: "删除",
      danger: true,
    );
    if (ok != true || !mounted) return;

    final path = track.localPath;
    try {
      if (path != null && await File(path).exists()) {
        await File(path).delete();
      }
    } catch (e) {
      print("删除下载文件失败：$e");
      if (mounted) AppToast.show(context, "文件删除失败，请检查存储权限");
      return;
    }
    await TrackRepository().clearDownloaded(track.id);
    ref.invalidate(downloadedTracksProvider);
    if (mounted) AppToast.show(context, "已删除下载");
  }
}

class _TaskTile extends ConsumerWidget {
  final DownloadTask task;

  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final failed = task.status == DownloadTaskStatus.failed;
    final status = switch (task.status) {
      DownloadTaskStatus.queued => "排队中",
      DownloadTaskStatus.downloading => "下载中 ${(task.progress * 100).round()}%",
      DownloadTaskStatus.completed => "已完成",
      DownloadTaskStatus.paused => "已暂停 · 继续时校验续传，必要时重新下载",
      DownloadTaskStatus.failed => task.message ?? "下载失败",
    };

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoverPlaceholder(
                cover: task.track.effectiveCover,
                text: task.track.effectiveName,
                size: 44,
                radius: t.radiusSm,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.track.effectiveName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.fg,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.track.effectiveAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: t.fgDim),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: failed ? t.primary : t.fgMute,
                      ),
                    ),
                  ],
                ),
              ),
              if (failed)
                IconButton(
                  tooltip: "重试",
                  onPressed: () => ref
                      .read(downloadTasksProvider.notifier)
                      .retry(task.track),
                  icon: Icon(Icons.refresh, size: 20, color: t.primary),
                ),
              if (task.active)
                IconButton(
                    tooltip: "暂停",
                    onPressed: () => ref
                        .read(downloadTasksProvider.notifier)
                        .pause(task.track.id),
                    icon: Icon(Icons.pause, color: t.fg)),
              if (task.status == DownloadTaskStatus.paused)
                IconButton(
                    tooltip: "继续",
                    onPressed: () => ref
                        .read(downloadTasksProvider.notifier)
                        .start(task.track),
                    icon: Icon(Icons.play_arrow, color: t.primary)),
              if (task.status != DownloadTaskStatus.completed)
                IconButton(
                    tooltip: "取消下载",
                    onPressed: () => ref
                        .read(downloadTasksProvider.notifier)
                        .cancel(task.track),
                    icon: Icon(Icons.close, color: t.fgDim)),
            ],
          ),
          const SizedBox(height: 10),
          AuroraProgressBar(
            value: task.progress.clamp(0.0, 1.0),
            height: 3,
            showThumb: false,
          ),
        ],
      ),
    );
  }
}
