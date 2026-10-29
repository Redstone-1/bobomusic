import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../origin_sdk/bili/bili_api_error.dart";
import "../../origin_sdk/qq/qq_api.dart";
import "../../core/overlays/app_loading.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/prefs/app_prefs.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/track.dart" hide OriginType;
import "../../data/mappers.dart";
import "../../data/origin_service.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/bili/bili_api.dart";
import "../../origin_sdk/origin_types.dart";
import "../../data/models/playlist.dart";
import "../download/download_actions.dart";
import "../download/download_tasks.dart";
import "../playlist/add_to_playlist_sheet.dart";
import "../player/mini_player_bar.dart";
import "../player/playback_provider.dart";
import "../player/player_card_page.dart";
import "../playlist/playlist_detail_page.dart";
import "../playlist/playlists_provider.dart"
    show collectionsProvider, likedCountProvider, queueTracksProvider;

/// 搜索音源（默认 B 站；仅本页生效，不再写全局设置）
enum _SearchSource {
  bili("B站"),
  kuwo("酷我"),
  netease("网易"),
  qq("QQ"),
  qianqian("千千");

  final String label;
  const _SearchSource(this.label);
}

const _kSearchHistory = "search_history";
const _kSearchHistoryMax = 10;

/// 搜索历史维护（纯函数，便于单测）：新词置顶、重复词去重前移、最多 10 条
List<String> updateSearchHistory(List<String> history, String keyword) {
  final q = keyword.trim();
  if (q.isEmpty) return history;
  return [
    q,
    for (final h in history)
      if (h != q) h,
  ].take(_kSearchHistoryMax).toList();
}

/// 搜索页（S3.3 接真搜索）：单曲/多P歌单结果 + 三态
/// 防抖 300ms；结果不入库（点歌/收藏动作才落库）
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  Object? _error;
  String _query = "";
  List<SearchItem> _results = [];
  _SearchSource _source = _SearchSource.bili;

  /// 翻页加载：当前已取页 / 是否还有下一页 / 翻页中 / 请求序号（新搜索作废在途翻页）
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _seq = 0;

  /// 搜索历史（SharedPreferences 持久；聚焦且无关键词时展示，最多 10 条）
  List<String> _history = [];

  /// 搜索结果行的快速收藏：库内已喜欢 id + 本地覆盖（写库不刷新结果列表）
  Set<String> _likedIds = {};
  final Map<String, bool> _likedOverrides = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _history = appPrefs.getStringList(_kSearchHistory) ?? const [];
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    _loadLikedIds();
  }

  Future<void> _loadLikedIds() async {
    try {
      final liked = await TrackRepository().likedTracks();
      if (!mounted) return;
      setState(() => _likedIds = {for (final t in liked) t.id});
    } catch (_) {
      // 喜欢态拿不到按未喜欢展示，不影响搜索
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _persistHistory(List<String> history) {
    // 必须 setState：清空/单条删除/搜索记入都靠它刷新历史面板（否则点了没反应）
    if (mounted) setState(() => _history = history);
    appPrefs.setStringList(_kSearchHistory, history);
  }

  void _onChanged() {
    final q = _controller.text.trim();
    if (q == _query) return;
    _query = q;
    // 输入变化立即作废旧请求，不能等防抖结束后才隔离旧词响应。
    _seq++;
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  /// 切换音源：清空旧结果并立即重搜当前关键词（默认 B 站）
  void _setSource(_SearchSource source) {
    if (_source == source) return;
    _debounce?.cancel();
    _seq++;
    setState(() {
      _source = source;
      _results = [];
      _error = null;
    });
    final q = _controller.text.trim();
    if (q.isNotEmpty) _search(q);
  }

  /// 当前选中音源的 API 实例（全局单例，测试可整体替换）
  OriginService get _activeApi => switch (_source) {
        _SearchSource.bili => biliApi,
        _SearchSource.kuwo => kuwoApi,
        _SearchSource.netease => neteaseApi,
        _SearchSource.qq => qqApi,
        _SearchSource.qianqian => qianqianApi,
      };

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _page = 1;
      _hasMore = true;
      _loadingMore = false;
    });
    try {
      // 本页音源选择（默认 B 站）；各源共用 OriginService 契约
      final api = _activeApi;
      final resp = await api.search(SearchParams(keyword: q, page: 1));
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = resp.data;
        _page = resp.current;
        _loading = false;
        _hasMore = _evalHasMore(resp);
      });
      // 搜索成功后记入历史（失败不记，避免污染）
      _persistHistory(updateSearchHistory(_history, q));
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// 由响应判断是否还有下一页：有总数按页推算；无总数先乐观认为有，
  /// 由 _loadMore 的空页/去重兜底
  bool _evalHasMore(SearchResponse resp) {
    if (resp.hasMore != null) return resp.hasMore!;
    if (resp.data.isEmpty) return false;
    if (resp.total <= 0) return true;
    return resp.current * resp.pageSize < resp.total;
  }

  /// 触底加载下一页：按 id 去重追加（音源若忽略页码重复返回，也能正确判到底）
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _query.isEmpty) return;
    final seq = _seq;
    final api = _activeApi;
    setState(() => _loadingMore = true);
    try {
      final resp = await api.search(
        SearchParams(keyword: _query, page: _page + 1),
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _loadingMore = false;
        final seen = {for (final r in _results) r.id};
        final fresh = <SearchItem>[];
        for (final r in resp.data) {
          if (seen.add(r.id)) fresh.add(r);
        }
        _results = [..._results, ...fresh];
        // QQ 可补查多个原始页，继续从实际消费的页码翻页；纯过滤空页仍可继续。
        _page = resp.current;
        _hasMore = _evalHasMore(resp) &&
            (fresh.isNotEmpty || (resp.data.isEmpty && resp.hasMore == true));
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _loadingMore = false);
      AppToast.show(context, e is QqApiError
          ? e.message
          : e is BiliApiError ? e.message : "加载失败，上滑重试");
    }
  }

  // 点歌：入库（后续喜欢/队列的落点）→ 只开播不弹卡；
  // 上下文 = 搜索结果中的单曲集合（§3.4-4）
  void _playTrack(Track track) {
    TrackRepository().upsert(track);
    final singles = [
      for (final item in _results)
        if ((item.musicList?.length ?? 0) <= 1) item.toTrack(),
    ];
    PlayerCardPage.start(context, ref, track, queue: singles);
  }

  /// 单曲点击（对齐 2.7.0：列表卡片不带合集标记，必须先拉 view 详情再分流——
  /// 多P 与合集进次级列表，真单曲才播放，从根上消灭"拿合集 id 取流必失败"）：
  /// ① detail 是多P（orderName）→ 合集列表页；
  /// ② detail.isSeasonDisplay（属于 UGC 合集）→ searchSeason 拉成员 → 合集列表页；
  /// ③ 真单曲 → 播放
  Future<void> _playWithResolve(SearchItem item) async {
    // 酷我无合集概念，单曲直接播（view/searchSeason 均为 B 站接口）
    if (item.origin != OriginType.bili) {
      _playTrack(item.toTrack());
      return;
    }
    AppLoading.show(msg: "加载中…");
    try {
      final detail = await biliApi.searchDetail(item.id);
      if (!mounted) return;
      final embedded = musicItemsToTracks(detail.musicList ?? const []);
      if (detail.type == SearchType.orderName && embedded.length > 1) {
        _pushCollectionDetail(detail.name, detail.cover, item.id, embedded);
        return;
      }
      final season = detail.ugcSeason;
      if (season != null && biliApi is BiliApi) {
        // searchSeason 是 B 站特有接口，不在 OriginService 抽象上
        final collection = await (biliApi as BiliApi)
            .searchSeason(season.mid, season.seasonId);
        if (!mounted) return;
        final tracks = musicItemsToTracks(collection?.musicList ?? const []);
        if (tracks.isNotEmpty) {
          _pushCollectionDetail(
            collection!.meta.name,
            collection.meta.cover,
            "${collection.meta.seasonId}",
            tracks,
          );
          return;
        }
      }
      // 真单曲 → 播放：用详情条目（id 带 cid；搜索条目无 cid，取流会再补一次 view）
      _playTrack(detail.toTrack());
    } catch (_) {
      if (mounted) AppToast.show(context, "加载失败，请重试");
    } finally {
      AppLoading.dismiss();
    }
  }

  // 多P歌单 → 收藏为合集（type=collection，曲目逐个入库）
  Future<void> _collectOrder(SearchItem item) async {
    AppLoading.show(msg: "收藏合集中…");
    try {
      final tracks = await _fetchCollectionTracks(item);
      final repo = PlaylistRepository();
      final pl = await repo.create(item.name, type: PlaylistType.collection);
      for (final t in tracks) {
        await TrackRepository().upsert(t);
        await repo.addTrack(pl.id, t.id);
      }
      ref.invalidate(collectionsProvider);
      if (mounted) AppToast.show(context, "已收藏「${item.name}」");
    } catch (_) {
      if (mounted) AppToast.show(context, "收藏失败：同名歌单已存在");
    } finally {
      AppLoading.dismiss();
    }
  }

  /// 取合集全部曲目（收藏/整包操作共用）：
  /// 内嵌多P曲目直用；UGC 合集（season）走 searchSeason；其余合集条目拉 view 详情
  Future<List<Track>> _fetchCollectionTracks(SearchItem item) async {
    final embedded = musicItemsToTracks(item.musicList ?? const []);
    if (embedded.length > 1) return embedded;
    final season = item.ugcSeason;
    if (season != null && biliApi is BiliApi) {
      // searchSeason 是 B 站特有接口，不在 OriginService 抽象上
      final detail =
          await (biliApi as BiliApi).searchSeason(season.mid, season.seasonId);
      return musicItemsToTracks(detail?.musicList ?? const []);
    }
    final view = await biliApi.searchDetail(item.id);
    return musicItemsToTracks(view.musicList ?? const []);
  }

  /// 快速收藏（搜索行心形）：先入库再写喜欢；列表不刷新，本地覆盖即时变红/变空
  void _toggleLike(Track track, bool liked) {
    TrackRepository().upsert(track);
    TrackRepository().setLiked(track.id, liked);
    ref.invalidate(likedCountProvider);
    setState(() => _likedOverrides[track.id] = liked);
  }

  /// 合集点击：进次级列表页（合集不是可播单曲，直接播必失败——所有者明确）。
  /// 内嵌多P带曲直跳；season/无内嵌曲目先拉成员再进页
  Future<void> _openCollection(SearchItem item) async {
    final embedded = musicItemsToTracks(item.musicList ?? const []);
    if (embedded.length > 1) {
      _pushCollectionDetail(item.name, item.cover, item.id, embedded);
      return;
    }
    AppLoading.show(msg: "加载合集中…");
    try {
      final tracks = await _fetchCollectionTracks(item);
      if (!mounted) return;
      if (tracks.isEmpty) {
        AppToast.show(context, "该合集暂无曲目");
        return;
      }
      _pushCollectionDetail(item.name, item.cover, item.id, tracks);
    } catch (_) {
      if (mounted) AppToast.show(context, "合集加载失败，请重试");
    } finally {
      AppLoading.dismiss();
    }
  }

  void _pushCollectionDetail(
    String name,
    String cover,
    String id,
    List<Track> tracks,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailPage(
          playlist: Playlist(
            id: "bili:$id",
            name: name,
            type: PlaylistType.collection,
          ),
          tracks: tracks,
          trackCover: cover.isEmpty ? null : cover,
        ),
      ),
    );
  }

  /// 合集更多菜单：先取全曲目再展示整包操作（全部加入待播放 / 全部下载）
  Future<void> _showCollectionActions(SearchItem item) async {
    AppLoading.show(msg: "加载合集中…");
    List<Track> tracks;
    try {
      tracks = await _fetchCollectionTracks(item);
    } catch (_) {
      if (mounted) AppToast.show(context, "合集加载失败，请重试");
      return;
    } finally {
      AppLoading.dismiss();
    }
    if (!mounted) return;
    if (tracks.isEmpty) {
      AppToast.show(context, "该合集暂无曲目");
      return;
    }
    AppSheet.show(
      context,
      title: item.name,
      actions: [
        AppSheetAction(
          icon: Icons.playlist_add,
          label: "全部加入待播放（${tracks.length} 首）",
          onTap: () async {
            for (final track in tracks) {
              await TrackRepository().upsert(track);
              await QueueRepository().append(track.id);
            }
            ref.invalidate(queueTracksProvider);
            if (mounted) AppToast.show(context, "已加入播放队列");
          },
        ),
        AppSheetAction(
          icon: Icons.download_outlined,
          label: "全部下载（${tracks.length} 首）",
          onTap: () {
            // 走下载任务层静默启动，统一一条汇总提示（逐曲 toast 会刷屏）
            final notifier = ref.read(downloadTasksProvider.notifier);
            for (final track in tracks) {
              notifier.start(track);
            }
            if (mounted) AppToast.show(context, "已开始下载 ${tracks.length} 首");
          },
        ),
      ],
    );
  }

  /// 单曲结果操作：插队/追加（播放队列，§3.4-5）
  void _showTrackActions(Track track) {
    AppSheet.show(
      context,
      title: track.name,
      actions: [
        AppSheetAction(
          icon: Icons.library_add_outlined,
          label: "加入歌单",
          onTap: () => showAddToPlaylistSheet(context, ref, track),
        ),
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: "下一首播放",
          onTap: () async {
            await TrackRepository().upsert(track);
            await QueueRepository().insertNext(track.id, atPosition: 0);
            ref.invalidate(queueTracksProvider);
            if (mounted) AppToast.show(context, "已设为下一首播放");
          },
        ),
        AppSheetAction(
          icon: Icons.playlist_add,
          label: "加入待播放",
          onTap: () async {
            await TrackRepository().upsert(track);
            await QueueRepository().append(track.id);
            ref.invalidate(queueTracksProvider);
            if (mounted) AppToast.show(context, "已加入播放队列");
          },
        ),
        // 本地曲无需下载（OriginType 在 UI/SDK 各有一套，按 name 比较避免歧义）
        if (track.origin.name != "local")
          AppSheetAction(
            icon: Icons.download_outlined,
            label: "下载",
            onTap: () => downloadTrack(context, track),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final currentTrackId = ref.watch(
      playbackProvider.select((s) => s.track?.id),
    );
    final queryEmpty = _controller.text.trim().isEmpty;
    // 聚焦且无关键词且历史非空 → 展示历史面板（否则走空态覆盖层）
    final showHistory = _focus.hasFocus && queryEmpty && _history.isNotEmpty;

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            // 头部（返回/搜索框/音源）固定；空态覆盖只占头部以下，键盘压缩时
            // 由 FittedBox 等比缩小，不会遮挡头部（2026-10-29 真机反馈）
            child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 头部固定区：返回 + 搜索框 + 音源选择
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: BackLink(),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _controller,
                            focusNode: _focus,
                            autofocus: true,
                            onChanged: (_) => _onChanged(),
                            style: TextStyle(fontSize: 14.5, color: t.fg),
                            decoration: InputDecoration(
                              hintText: "搜索歌曲 / 歌手 / 合集",
                              hintStyle:
                                  TextStyle(fontSize: 14, color: t.fgMute),
                              prefixIcon: Icon(Icons.search,
                                  size: 20, color: t.fgDim),
                              filled: true,
                              fillColor: t.surface,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: t.hairline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: t.hairline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: t.primary),
                              ),
                            ),
                          ),
                          // 音源选择（默认 B 站；本页切换，不写全局设置）。
                          // 等宽胶囊一行平铺：保留玻璃 chips 视觉语言，撑满搜索框宽度
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (final (i, source)
                                  in _SearchSource.values.indexed) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: GlassChip(
                                    label: source.label,
                                    selected: _source == source,
                                    onTap: () => _setSource(source),
                                    // 等分后每枚约 55-64dp，默认 16 水平留白会把
                                    // 两字标签挤折行，紧凑留白保证单行
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              // 触底前 400px 预取下一页（仅纵向列表）
                              if (n.metrics.axis == Axis.vertical &&
                                  n.metrics.pixels >=
                                      n.metrics.maxScrollExtent - 400) {
                                _loadMore();
                              }
                              return false;
                            },
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 10, 20, 110),
                              children: [
                                // 搜索历史：聚焦且无关键词时展示（可单条删/清空）
                                if (showHistory) ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "搜索历史",
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: t.fg,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            _persistHistory(const []),
                                        child: Text(
                                          "清空",
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: t.fgDim),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  for (final (i, keyword)
                                      in _history.indexed)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(
                                          t.radiusMd),
                                      onTap: () =>
                                          _controller.text = keyword,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 7),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.history,
                                              size: 17,
                                              color: t.fgMute,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                keyword,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  color: t.fgDim,
                                                ),
                                              ),
                                            ),
                                            // 单条删除（不触发搜索）
                                            GestureDetector(
                                              behavior:
                                                  HitTestBehavior.opaque,
                                              onTap: () => _persistHistory([
                                                for (final (j, h) in
                                                    _history.indexed)
                                                  if (j != i) h,
                                              ]),
                                              child: Icon(
                                                Icons.close,
                                                size: 16,
                                                color: t.fgMute,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                                // 刷新/首搜统一用细进度线提示（所有者 2026-10-27 定：删骨架屏）
                                if (_controller.text.trim().isNotEmpty &&
                                    _loading)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 10),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        minHeight: 2,
                                        color: t.primary,
                                        backgroundColor: t.surface2,
                                      ),
                                    ),
                                  ),
                                for (final item in _results)
                                  // 合集（orderName 或多P）→ 歌单行进详情，绝不直接播放；
                                  // 单曲 → 歌曲行（musicList 首条带播放 id）
                                  if (item.type == SearchType.orderName ||
                                      (item.musicList?.length ?? 0) > 1)
                                    _OrderResultTile(
                                      item: item,
                                      onTap: () => _openCollection(item),
                                      onCollect: () => _collectOrder(item),
                                      onMorePressed: () =>
                                          _showCollectionActions(item),
                                    )
                                  else
                                    Builder(
                                      builder: (context) {
                                        final track = item.toTrack();
                                        return SongListTile(
                                          track: track,
                                          playing:
                                              track.id == currentTrackId,
                                          // 波浪左侧快速收藏心形（真机反馈要求）：
                                          // 初始态取库内喜欢集合，点击后本地覆盖即时变化
                                          likedHeart:
                                              _likedOverrides[track.id] ??
                                                  _likedIds.contains(
                                                      track.id),
                                          onHeartTap: (liked) =>
                                              _toggleLike(track, liked),
                                          // 对齐 2.7.0：点击先拉详情分流
                                          onTap: () =>
                                              _playWithResolve(item),
                                          onMorePressed: () =>
                                              _showTrackActions(track),
                                        );
                                      },
                                    ),
                                // 翻页尾态：取页中转圈；没有更多结果时提示到底
                                if (_loadingMore)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    child: Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: t.primary,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (_results.isNotEmpty && _hasMore && !_loading)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Center(
                                      child: GlassChip(label: "加载更多", onTap: _loadMore),
                                    ),
                                  )
                                else if (_results.isNotEmpty &&
                                    !_hasMore &&
                                    !_loading)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 12),
                                    child: Center(
                                      child: Text(
                                        "到底了",
                                        style: TextStyle(
                                            fontSize: 12, color: t.fgMute),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // 空态覆盖：初始引导（键盘在场同样显示，FittedBox 等比
                          // 缩小不遮挡头部）/ 搜索失败 / 无结果（历史在场时让位）
                          if (queryEmpty && !showHistory)
                            const Positioned.fill(
                              child: EmptyState(
                                asset:
                                    "assets/illustrations/empty_search.svg",
                                title: "输入关键词开始搜索",
                                subtitle:
                                    "支持 B站 / 酷我 / 网易 / QQ / 千千 音源",
                              ),
                            )
                          else if (!queryEmpty &&
                              !_loading &&
                              _results.isEmpty)
                            Positioned.fill(
                              child: _error != null
                                  ? EmptyState(
                                      asset:
                                          "assets/illustrations/empty_alert.svg",
                                      title: "搜索失败",
                                      subtitle: _error is BiliApiError
                                          ? (_error as BiliApiError).message
                                          : _error is QqApiError
                                              ? (_error as QqApiError).message
                                              : "检查网络后重试",
                                      action: GlassChip(
                                        label: "重试",
                                        onTap: () => _search(_query),
                                      ),
                                    )
                                  : EmptyState(
                                      asset:
                                          "assets/illustrations/empty_search.svg",
                                      title: _hasMore
                                          ? "暂未找到可播放歌曲"
                                          : "没有找到与“$_query”相关的内容",
                                      subtitle: _hasMore
                                          ? "可继续查找更多结果"
                                          : "换个关键词试试",
                                      action: _hasMore
                                          ? GlassChip(
                                              label: _loadingMore ? "查找中…" : "继续查找",
                                              onTap: () {
                                                if (!_loadingMore) _loadMore();
                                              },
                                            )
                                          : null,
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
}
/// 合集/多P 歌单结果行：封面 + 标题（带合集 tag）+ 收藏 + 更多（整包操作）
class _OrderResultTile extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onTap;
  final VoidCallback onCollect;
  final VoidCallback? onMorePressed;

  const _OrderResultTile({
    required this.item,
    required this.onTap,
    required this.onCollect,
    this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final count = item.musicList?.length ?? 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radiusMd),
      splashColor: t.surface2,
      highlightColor: t.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            CoverPlaceholder(
              cover: item.cover,
              text: item.name,
              size: 48,
              radius: t.radiusSm,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // 合集标识：一眼区分"这是歌单不是单曲"
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: t.coverBadgeBg,
                        ),
                        child: Text(
                          "合集",
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.0,
                            fontWeight: FontWeight.w700,
                            color: t.coverBadgeFg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          count > 0 ? "$count 首 · ${item.author}" : item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: t.fgDim),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCollect,
              icon: const Icon(Icons.bookmark_add_outlined),
              iconSize: 20,
              color: t.primary,
              tooltip: "收藏为歌单",
            ),
            IconButton(
              onPressed: onMorePressed,
              icon: const Icon(Icons.more_vert),
              iconSize: 18,
              color: t.fgMute,
              tooltip: "更多",
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

