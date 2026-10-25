import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/permissions/audio_permission.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/skeleton.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/local_audio_scanner.dart";
import "../../data/models/playlist.dart";
import "../../data/models/track.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../download/download_actions.dart";
import "../player/mini_player_bar.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "playlists_provider.dart"
    show
        likedCountProvider,
        localCountProvider,
        playlistDetailTracksProvider,
        queueTracksProvider;

/// 歌单详情（对齐原型 renderSub/playlist）
/// 两种数据模式：
/// - [tracks] 非空：内存注入（热门歌手/合集等外部数据源）
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

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  late Future<List<Track>> _future;
  int _reloadSeq = 0;
  bool _scanning = false;

  /// 我喜欢列表的心形本地覆盖（trackId → 当前显示态）：
  /// 取消收藏写库但不刷新列表，心形即时变化，下次进入页面重读库
  final _likedOverrides = <String, bool>{};

  bool get _isLocal => widget.playlist.id == "builtin:local";

  bool get _isLiked => widget.playlist.id == "builtin:liked";

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Track>> _load() async {
    if (widget.tracks != null) return widget.tracks!;
    if (widget.playlist.id == "builtin:liked") {
      return TrackRepository().likedTracks();
    }
    if (_isLocal) {
      return TrackRepository().localTracks();
    }
    return PlaylistRepository().items(widget.playlist.id);
  }

  void _retry() {
    setState(() {
      _reloadSeq++;
      _future = _load();
    });
  }

  /// 本地扫描（C3）：权限 → 后台扫描 → 同步入库 → 失效相关 provider → toast
  Future<void> _scan() async {
    final granted = await requestAudioPermission();
    if (!granted) {
      if (mounted) AppToast.show(context, "未获得音频读取权限");
      return;
    }
    setState(() => _scanning = true);
    try {
      final result = await scanLocalLibrary();
      await TrackRepository().syncLocalTracks(result.tracks);
      ref.invalidate(playlistDetailTracksProvider);
      ref.invalidate(localCountProvider);
      if (!mounted) return;
      AppToast.show(
        context,
        result.failed.isEmpty
            ? "扫描完成 · 共 ${result.tracks.length} 首"
            : "扫描完成 ${result.tracks.length} 首 · ${result.failed.length} 首读取失败",
      );
    } catch (e) {
      print("本地扫描失败: $e");
      if (mounted) AppToast.show(context, "扫描失败，请重试");
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );
    // 本地模式走 family provider（扫描 invalidate 后列表自动刷新）；
    // 库/注入模式沿用局部 Future（重试走 _reloadSeq）
    final localFuture = _isLocal
        ? ref.watch(playlistDetailTracksProvider(widget.playlist).future)
        : null;

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            // FutureBuilder 外提：空态走覆盖层（Stack + Positioned.fill 居中于
            // 列表可视区且不占列表流，透明区域点击穿透到 BackLink/头部按钮）
            child: FutureBuilder(
              key: ValueKey(_reloadSeq),
              future: localFuture ?? _future,
              builder: (context, snap) {
                final loading =
                    snap.connectionState != ConnectionState.done || _scanning;
                final tracks = snap.data;
                final empty = !loading && !snap.hasError && tracks != null && tracks.isEmpty;
                return Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: BackLink(),
                        ),
                        PageHeader(
                          title: widget.playlist.name,
                          subtitle: "播放全部",
                          // 头部按钮：本地 = 重新扫描；我喜欢 = 刷新（重读库）；
                          // 其余保持随机占位
                          trailing: _isLocal
                              ? GlassIconButton(
                                  icon: const Icon(Icons.refresh),
                                  onTap: _scanning ? null : _scan,
                                )
                              : _isLiked
                                  ? GlassIconButton(
                                      icon: const Icon(Icons.refresh),
                                      onTap: () {
                                        ref.invalidate(
                                          playlistDetailTracksProvider,
                                        );
                                        ref.invalidate(likedCountProvider);
                                      },
                                    )
                                  : GlassIconButton(
                                      icon: const Icon(Icons.shuffle_outlined),
                                      onTap: () {},
                                    ),
                        ),
                        const SizedBox(height: 14),
                        if (loading)
                          const SkeletonListView(rows: 6)
                        else if (snap.hasError)
                          EmptyState(
                            compact: true,
                            emoji: "⚠️",
                            title: "加载失败",
                            subtitle: "点击重试",
                            action: GlassChip(label: "重试", onTap: _retry),
                          )
                        else if (tracks!.isNotEmpty)
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
                                      : (liked) {
                                          TrackRepository()
                                              .setLiked(track.id, liked);
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
                                    title: track.name,
                                    actions: [
                                      AppSheetAction(
                                        icon: Icons.queue_music_outlined,
                                        label: "下一首播放",
                                        onTap: () async {
                                          await TrackRepository().upsert(track);
                                          await QueueRepository().insertNext(
                                            track.id,
                                            atPosition: 0,
                                          );
                                          ref.invalidate(queueTracksProvider);
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
                                          ref.invalidate(queueTracksProvider);
                                          if (context.mounted) {
                                            AppToast.show(context, "已加入播放队列");
                                          }
                                        },
                                      ),
                                      if (track.origin != OriginType.local)
                                        AppSheetAction(
                                          icon: Icons.download_outlined,
                                          label: "下载",
                                          onTap: () =>
                                              downloadTrack(context, track),
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
                                emoji: "🎧",
                                title: "本地音乐是空的",
                                subtitle: "扫描设备存储中的音频文件",
                                action: GlassChip(
                                  label: "扫描本地音乐",
                                  onTap: _scan,
                                ),
                              )
                            : const EmptyState(
                                emoji: "🎵",
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
