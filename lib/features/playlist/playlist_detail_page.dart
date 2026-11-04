import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/permissions/audio_permission.dart";
import "../../core/permissions/file_delete_permission.dart";
import "../../core/platform/app_platform.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/app_search_field.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../data/local_audio_importer.dart";
import "../../data/local_audio_scanner.dart";
import "../../data/models/playlist.dart";
import "../../data/models/track.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../download/download_actions.dart";
import "../playlist/add_to_playlist_sheet.dart";
import "../player/mini_player_bar.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "local_scan_controller.dart";
import "local_library_directories.dart";
import "local_scan_panel.dart";
import "playlists_provider.dart"
    show
        likedCountProvider,
        localCountProvider,
        playlistDetailTracksProvider,
        playlistsProvider,
        playlistInfoProvider,
        queueEntriesProvider;
import "scan_failures_dialog.dart";
import "track_edit_dialog.dart";
import "playlist_edit_dialog.dart";
import "batch_rename_page.dart";
import "batch_track_edit_page.dart";

/// 歌单详情（对齐原型 renderSub/playlist）
/// 两种数据模式：
/// - [tracks] 非空：内存注入（合集等外部数据源）
/// - [tracks] 为空：按 [playlist] 从库取数（我喜欢 → likedTracks；本地 → localTracks；自定义 → items）
/// [trackCover] = 曲目行统一封面（如歌手歌单共用歌手写真），空则各行用自身封面
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final Playlist playlist;
  final List<Track>? tracks;
  final String? trackCover;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    this.tracks,
    this.trackCover,
  });

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage>
    with SingleTickerProviderStateMixin {
  bool _scanning = false;

  /// 流式扫描状态；非空时列表区域显示扫描舱
  LocalScanController? _scanController;

  /// 歌曲搜索（本地/喜欢列表：实时过滤歌名/歌手）
  final _searchController = TextEditingController();
  String _query = "";

  /// 重扫/导入中刷新按钮的持续旋转（点击即刻可见反馈，不再"无响应数秒"）
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// 我喜欢列表的心形本地覆盖（trackId → 当前显示态）：
  /// 取消收藏写库但不刷新列表，心形即时变化，下次进入页面重读库
  final _likedOverrides = <String, bool>{};

  bool get _isLocal => widget.playlist.id == "builtin:local";

  bool get _isLiked => widget.playlist.id == "builtin:liked";

  void _openBatchEdit(List<Track>? tracks, BatchTrackEditMode mode) {
    if (tracks == null || tracks.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => mode == BatchTrackEditMode.rename
            ? BatchRenamePage(tracks: List.of(tracks))
            : BatchTrackEditPage(tracks: List.of(tracks), mode: mode)));
  }

  List<AppSheetAction> _batchActions(List<Track>? tracks) => [
    AppSheetAction(icon: Icons.drive_file_rename_outline, label: "批量重命名",
        onTap: () => _openBatchEdit(tracks, BatchTrackEditMode.rename)),
    AppSheetAction(icon: Icons.person_outline, label: "批量设置歌手",
        onTap: () => _openBatchEdit(tracks, BatchTrackEditMode.author)),
    AppSheetAction(icon: Icons.image_outlined, label: "批量设置封面",
        onTap: () => _openBatchEdit(tracks, BatchTrackEditMode.cover)),
  ];

  Widget _batchEditButton(List<Track>? tracks) => Tooltip(message: "批量编辑",
    child: GlassIconButton(key: const Key("batch_rename_entry"),
        icon: const Icon(Icons.drive_file_rename_outline),
        onTap: tracks == null || tracks.isEmpty || _scanning ? null
            : () => AppSheet.show(context, title: "批量编辑", actions: _batchActions(tracks))));

  @override
  void dispose() {
    // 扫描中离开页面：停止 isolate；写库由 _scan 的 finally 收尾
    _scanController?.cancel();
    _spin.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 库内详情统一失效同一个 family，注入的合集列表保持内存数据源。
  void _reload() {
    if (widget.tracks == null) {
      ref.invalidate(playlistDetailTracksProvider(widget.playlist.id));
    } else {
      setState(() {});
    }
  }

  /// 本地扫描（C3）：权限 → 流式扫描/入库 → 失效 provider → 失败弹窗
  Future<void> _scan() async {
    final granted = await requestAudioPermission();
    if (!granted) {
      if (mounted) AppToast.show(context, "未获得音频读取权限");
      return;
    }
    List<String>? directories;
    if (ref.read(appPlatformProvider).usesDesktopLayout) {
      var selectedDirectories = ref.read(localLibraryDirectoriesProvider);
      if (selectedDirectories.isEmpty) {
        await _chooseDirectory();
        if (!mounted) return;
        selectedDirectories = ref.read(localLibraryDirectoriesProvider);
        if (selectedDirectories.isEmpty) return;
      }
      directories = selectedDirectories;
    }
    final roots = directories?.map(Directory.new).toList();
    final controller = LocalScanController(
        taskFactory:
            roots == null ? null : () => scanLocalLibraryTask(roots: roots));
    setState(() {
      _scanning = true;
      _scanController = controller;
    });
    try {
      await controller.start();
      if (!mounted) return;
      // 小库扫描极快时也让完成态停留一瞬，避免扫描舱一闪而过
      if (controller.phase == LocalScanPhase.done) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
      }
      ref.invalidate(playlistDetailTracksProvider(widget.playlist.id));
      ref.invalidate(localCountProvider);
      if (controller.cancelled) return;
      if (controller.phase == LocalScanPhase.failed) {
        AppToast.show(context, "扫描失败，请重试");
      } else if (controller.failures.isNotEmpty) {
        await showScanFailuresDialog(context, controller.failures);
      } else {
        AppToast.show(context, "扫描完成 · 共 ${controller.indexed} 首");
      }
    } catch (e) {
      print("本地扫描失败: $e");
      if (mounted) AppToast.show(context, "扫描失败，请重试");
    } finally {
      if (mounted) {
        setState(() {
          _scanController = null;
          _scanning = false;
        });
      }
      controller.dispose();
    }
  }

  /// 从文件导入（iOS/桌面）：file_picker 选择 → 复制到文档目录 → 逐条 upsert
  /// 不做全量 sync，避免把 Android 全盘扫描的其它本地曲目误删
  Future<void> _importFiles() async {
    setState(() => _scanning = true);
    try {
      final imported = await pickAndImportAudioFiles();
      if (imported.isEmpty) return;
      for (final track in imported) {
        await TrackRepository().upsert(track);
      }
      ref.invalidate(playlistDetailTracksProvider(widget.playlist.id));
      ref.invalidate(localCountProvider);
      if (!mounted) return;
      AppToast.show(context, "已导入 ${imported.length} 首");
    } catch (e) {
      print("导入本地文件失败：$e");
      if (mounted) AppToast.show(context, "导入失败，请重试");
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _chooseDirectory() async {
    try {
      final path = await ref.read(musicDirectoryPickerProvider)();
      if (path == null || !mounted) return;
      await ref.read(localLibraryDirectoriesProvider.notifier).add(path);
      if (mounted) AppToast.show(context, "已添加音乐文件夹");
    } catch (error) {
      print("添加扫描目录失败：$error");
      if (mounted) AppToast.show(context, "添加目录失败，请重试");
    }
  }

  void _manageDirectories() {
    final directories = ref.read(localLibraryDirectoriesProvider);
    AppSheet.show(context, title: "扫描目录", actions: [
      AppSheetAction(
          icon: Icons.create_new_folder_outlined,
          label: "添加音乐文件夹",
          onTap: _chooseDirectory),
      for (final path in directories)
        AppSheetAction(
            icon: Icons.folder_off_outlined,
            label: "移除：$path",
            onTap: () async {
              final confirmed = await AppDialog.confirm(context,
                  title: "移除扫描目录",
                  message: "停止扫描此目录，已入库音乐和原文件都会保留。\n$path",
                  confirmText: "移除");
              if (confirmed != true || !mounted) return;
              try {
                await ref
                    .read(localLibraryDirectoriesProvider.notifier)
                    .remove(path);
              } catch (error) {
                print("移除目录失败：$error");
                if (mounted) AppToast.show(context, "目录设置保存失败");
              }
            }),
    ]);
  }

  /// 删除本地曲目：默认仅移出曲库（外键级联清队列/歌单引用），
  /// 复选框勾选时先删源文件再移出曲库；文件删不掉则保留曲目，可重试
  /// 移出歌单（自定义歌单行内操作）：删除关联后重读本页列表并刷新目录计数；
  /// 曲目本身保留，可再次通过「加入歌单」加回。
  /// 移出歌单后精确失效该 ID 对应的详情数据源。
  Future<void> _removeFromPlaylist(Track track) async {
    await PlaylistRepository().removeTrack(widget.playlist.id, track.id);
    if (!mounted) return;
    ref.invalidate(playlistsProvider);
    _reload();
    AppToast.show(context, "已移出歌单");
  }

  /// 清除全部喜欢：二次确认后清空 liked_at 标记（曲目本身与歌单不受影响）
  Future<void> _clearLiked() async {
    final t = AuroraTokens.of(context);
    final ok = await AppDialog.show<bool>(
      context,
      title: "清除全部喜欢的歌曲？",
      content: Text(
        "将移除喜欢列表内全部歌曲；歌曲本身、歌单与播放队列不受影响。",
        style: TextStyle(fontSize: 13.5, height: 1.5, color: t.fgDim),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text("取消", style: TextStyle(color: t.fgDim)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            "清除",
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    await TrackRepository().clearLiked();
    if (!mounted) return;
    setState(_likedOverrides.clear);
    ref.invalidate(likedCountProvider);
    // 喜欢列表走 family provider：失效后自动重读为空态
    ref.invalidate(playlistDetailTracksProvider(widget.playlist.id));
    AppToast.show(context, "已清空喜欢列表");
  }

  Future<void> _deleteLocalTrack(Track track) async {
    final t = AuroraTokens.of(context);
    final deleteFile = ValueNotifier<bool>(false);
    final ok = await AppDialog.show<bool>(
      context,
      title: "删除歌曲",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "将从本地音乐移除「${track.name}」。",
            style: TextStyle(fontSize: 13.5, height: 1.5, color: t.fgDim),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: deleteFile,
            builder: (_, checked, __) => CheckboxListTile(
              value: checked,
              onChanged: (v) => deleteFile.value = v ?? false,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                "同时删除源文件",
                style: TextStyle(fontSize: 14, color: t.fg),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text("取消", style: TextStyle(color: t.fgDim)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            "删除",
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    final path = track.localPath;
    // 勾选删源文件时先删文件：失败则保留曲目，用户可再次进入菜单重试
    if (deleteFile.value && path != null && path.isNotEmpty) {
      // 分区存储：Android 11+ 的音频读权限不含删除，需要所有文件访问
      if (!await requestFileDeletePermission()) {
        if (mounted) AppToast.show(context, "未获得存储权限，无法删除源文件");
        return;
      }
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        print("删除本地源文件失败：$e");
        if (mounted) AppToast.show(context, "源文件删除失败，曲目已保留");
        return;
      }
    }
    try {
      await TrackRepository().delete(track.id);
      ref.invalidate(playlistDetailTracksProvider(widget.playlist.id));
      ref.invalidate(localCountProvider);
      ref.invalidate(queueEntriesProvider);
      if (!mounted) return;
      AppToast.show(context, "已删除");
    } catch (e) {
      print("删除本地曲目失败：$e");
      if (mounted) AppToast.show(context, "删除失败，请重试");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final custom = widget.tracks == null && widget.playlist.type == PlaylistType.custom;
    final playlist = custom
        ? ref.watch(playlistInfoProvider(widget.playlist.id)).value ?? widget.playlist
        : widget.playlist;
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );
    // 统一按歌单 ID 取数，重读期间保留上一份 AsyncValue 数据。
    final detailAsync = widget.tracks == null
        ? ref.watch(playlistDetailTracksProvider(widget.playlist.id))
        : AsyncData<List<Track>>(widget.tracks!);
    // 外部改变喜欢状态后 provider 重读：清掉行内心形覆盖，统一以库态为准
    if (_isLiked) {
      ref.listen(playlistDetailTracksProvider(widget.playlist.id), (_, __) {
        if (_likedOverrides.isNotEmpty) setState(_likedOverrides.clear);
      });
    }

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            child: Builder(
              builder: (context) {
                final raw = detailAsync.value;
                final hasError = detailAsync.hasError;
                final pending = raw == null && !hasError;
                final loading = pending || _scanning;
                // 扫描/导入进行中让刷新图标持续旋转（即时反馈，按钮同时禁用）
                if (_scanning) {
                  _spin.repeat();
                } else {
                  _spin.stop();
                }
                // 本地/喜欢列表搜索过滤（歌名/歌手，忽略大小写）；其余模式原样展示。
                // 空库覆盖层与「没有找到」空态都以 raw 为准，过滤只影响列表行
                final searchable = _isLocal || _isLiked;
                final query = _query.trim().toLowerCase();
                final tracks = (searchable && query.isNotEmpty && raw != null)
                    ? raw
                        .where(
                          (t) =>
                              t.effectiveName.toLowerCase().contains(query) ||
                              t.effectiveAuthor.toLowerCase().contains(query),
                        )
                        .toList()
                    : raw;
                final empty =
                    !loading && !hasError && raw != null && raw.isEmpty;
                return Stack(
                  children: [
                    ListView(
                      padding: EdgeInsets.fromLTRB(
                          20, 8, 20, DesktopContent.of(context) ? 24 : 110),
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: BackLink(),
                        ),
                        PageHeader(
                          title: playlist.name,
                          subtitle: _isLocal && DesktopContent.of(context)
                              ? "${ref.watch(localLibraryDirectoriesProvider).length} 个扫描目录"
                              : null,
                          // 头部按钮：本地 = 重新扫描；我喜欢 = 刷新（重读库）；
                          // 其余类型（自定义歌单/合集）不放占位按钮
                          trailing: _isLocal
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _batchEditButton(tracks),
                                    if (DesktopContent.of(context))
                                      GlassIconButton(
                                          icon: const Icon(
                                              Icons.folder_open_outlined),
                                          onTap: _scanning
                                              ? null
                                              : _manageDirectories),
                                    GlassIconButton(
                                      key: const Key("local_import"),
                                      icon:
                                          const Icon(Icons.file_open_outlined),
                                      onTap: _scanning ? null : _importFiles,
                                    ),
                                    const SizedBox(width: 8),
                                    GlassIconButton(
                                      // 扫描中图标持续旋转（即时反馈）
                                      icon: RotationTransition(
                                        turns: _spin,
                                        child: const Icon(Icons.refresh),
                                      ),
                                      onTap: _scanning ? null : _scan,
                                    ),
                                  ],
                                )
                              : _isLiked
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _batchEditButton(tracks),
                                        GlassIconButton(
                                          // 清除全部：二次确认后清空喜欢标记
                                          icon: const Icon(
                                            Icons.delete_sweep_outlined,
                                          ),
                                          onTap: raw == null || raw.isEmpty
                                              ? null
                                              : _clearLiked,
                                        ),
                                        const SizedBox(width: 8),
                                        GlassIconButton(
                                          icon: const Icon(Icons.refresh),
                                          // 喜欢列表走 family provider：失效后自动重读；
                                          // 顺带清心形本地覆盖
                                          onTap: () {
                                            _likedOverrides.clear();
                                            ref.invalidate(
                                              playlistDetailTracksProvider(
                                                widget.playlist.id,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    )
                                  : custom ? GlassIconButton(key: const Key("custom_playlist_more"),
                                      icon: const Icon(Icons.more_horiz),
                                      onTap: () => AppSheet.show(context, title: playlist.name, actions: [
                                        AppSheetAction(icon: Icons.edit_outlined, label: "编辑信息",
                                            onTap: () => showPlaylistEditDialog(context, ref, playlist)),
                                        if (tracks?.isNotEmpty == true) ..._batchActions(tracks),
                                      ])) : null,
                        ),
                        if (custom) Padding(padding: const EdgeInsets.only(top: 14),
                            child: Row(children: [
                              CoverPlaceholder(cover: playlist.cover, text: playlist.name, size: 64, radius: t.radiusMd),
                              const SizedBox(width: 14),
                              Text("${raw?.length ?? playlist.count} 首歌曲", style: TextStyle(color: t.fgDim)),
                            ])),
                        // 喜欢列表有内容时同样提供搜索（空库交给空态引导）
                        if (_isLocal ||
                            (_isLiked && raw != null && raw.isNotEmpty)) ...[
                          const SizedBox(height: 12),
                          AppSearchField(
                            controller: _searchController,
                            hintText: "搜索歌曲 / 歌手",
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (_scanController != null)
                          SizedBox(
                            height: (MediaQuery.sizeOf(context).height - 310)
                                .clamp(300.0, 560.0)
                                .toDouble(),
                            child: LocalScanPanel(
                              controller: _scanController!,
                              onCancel: () => _scanController?.cancel(),
                            ),
                          )
                        else if (hasError)
                          EmptyState(
                            compact: true,
                            emoji: "⚠️",
                            title: "加载失败",
                            subtitle: "点击重试",
                            action: GlassChip(
                              label: "重试",
                              // 按当前歌单 ID 精确失效后重读。
                              onTap: _reload,
                            ),
                          )
                        else if (query.isNotEmpty &&
                            raw != null &&
                            raw.isNotEmpty &&
                            tracks!.isEmpty)
                          EmptyState(
                            compact: true,
                            emoji: "🔍",
                            title: "没有找到「${_query.trim()}」",
                            subtitle: "换个关键词试试",
                            action: GlassChip(
                              label: "清除搜索",
                              onTap: () {
                                _searchController.clear();
                                setState(() => _query = "");
                              },
                            ),
                          )
                        else if (tracks != null && tracks.isNotEmpty)
                          Column(
                            children: [
                              for (final track in tracks)
                                SongListTile(
                                  track: track,
                                  playing: track.id == currentTrackId,
                                  coverOverride: widget.trackCover,
                                  // 我喜欢：行首心形快速取消收藏，
                                  // 写库但不刷新列表（心形局部更新，下次进入重读）
                                  likedHeart: _isLiked
                                      ? (_likedOverrides[track.id] ??
                                          track.liked)
                                      : null,
                                  onHeartTap: !_isLiked
                                      ? null
                                      : (liked) async {
                                          // 先落库再刷新计数，避免重读抢在写库前
                                          await TrackRepository()
                                              .setLiked(track.id, liked);
                                          if (!mounted) return;
                                          // 行内只更新心形不刷新列表，但计数要同步
                                          ref.invalidate(likedCountProvider);
                                          setState(() =>
                                              _likedOverrides[track.id] =
                                                  liked);
                                        },
                                  // 播放上下文 = 当前列表（§3.4-4）
                                  onTap: () => PlayerCardPage.start(
                                    context,
                                    ref,
                                    track,
                                    queue: tracks,
                                  ),
                                  onMorePressed: () => AppSheet.show(
                                    context,
                                    title: track.effectiveName,
                                    actions: [
                                      AppSheetAction(
                                        icon: Icons.edit_outlined,
                                        label: "编辑信息",
                                        onTap: () => showTrackEditDialog(
                                          context,
                                          ref,
                                          track,
                                        ),
                                      ),
                                      AppSheetAction(
                                        icon: Icons.library_add_outlined,
                                        label: "加入歌单",
                                        onTap: () => showAddToPlaylistSheet(
                                          context,
                                          ref,
                                          [track],
                                        ),
                                      ),
                                      AppSheetAction(
                                        icon: Icons.queue_music_outlined,
                                        label: "下一首播放",
                                        onTap: () async {
                                          await TrackRepository().upsert(track);
                                          await QueueRepository().insertNext(
                                            track.id,
                                            atPosition: 0,
                                          );
                                          ref.invalidate(queueEntriesProvider);
                                          if (context.mounted) {
                                            AppToast.show(context, "已设为下一首播放");
                                          }
                                        },
                                      ),
                                      AppSheetAction(
                                        icon: Icons.playlist_add,
                                        label: "加入待播放",
                                        onTap: () async {
                                          await TrackRepository().upsert(track);
                                          await QueueRepository()
                                              .append(track.id);
                                          ref.invalidate(queueEntriesProvider);
                                          if (context.mounted) {
                                            AppToast.show(context, "已加入播放队列");
                                          }
                                        },
                                      ),
                                      // 仅自定义歌单提供移出（我喜欢用行内心形取消，
                                      // 本地音乐用删除，合集详情无持久化）
                                      if (widget.playlist.type ==
                                          PlaylistType.custom)
                                        AppSheetAction(
                                          icon: Icons.playlist_remove,
                                          label: "移出歌单",
                                          onTap: () =>
                                              _removeFromPlaylist(track),
                                        ),
                                      if (track.origin != OriginType.local)
                                        AppSheetAction(
                                          icon: Icons.download_outlined,
                                          label: "下载",
                                          onTap: () =>
                                              downloadTrack(context, track),
                                        ),
                                      if (_isLocal)
                                        AppSheetAction(
                                          icon: Icons.delete_outline,
                                          label: "删除",
                                          danger: true,
                                          onTap: () => _deleteLocalTrack(track),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        SizedBox(height: t.radiusLg),
                      ],
                    ),
                    if (empty)
                      Positioned.fill(
                        child: _isLocal
                            ? EmptyState(
                                asset: "assets/illustrations/empty_search.svg",
                                title: "本地音乐是空的",
                                subtitle: "扫描设备存储或从文件导入音频",
                                action: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GlassChip(
                                      label: "扫描本地音乐",
                                      onTap: _scan,
                                    ),
                                    const SizedBox(width: 10),
                                    GlassChip(
                                      label: "从文件导入",
                                      onTap: _importFiles,
                                    ),
                                  ],
                                ),
                              )
                            : const EmptyState(
                                asset:
                                    "assets/illustrations/empty_collection.svg",
                                title: "歌单还是空的",
                                subtitle: "从广场搜索或本地扫描添加歌曲",
                              ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
