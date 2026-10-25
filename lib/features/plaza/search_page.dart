import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/skeleton.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/track.dart";
import "../../data/mappers.dart";
import "../../data/origin_service.dart";
import "../../data/repositories/playlist_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/origin_types.dart";
import "../../data/models/playlist.dart";
import "../player/mini_player_bar.dart";
import "../player/player_card_page.dart";
import "../playlist/playlist_detail_page.dart";
import "../playlist/playlists_provider.dart" show collectionsProvider;

/// 搜索页（S3.3 接 BiliApi 真搜索）：单曲/多P歌单结果 + 三态
/// 防抖 300ms；结果不入库（点歌/收藏动作才落库）
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  Object? _error;
  String _query = "";
  List<SearchItem> _results = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final q = _controller.text.trim();
    if (q == _query) return;
    _query = q;
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {});
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await biliApi.search(SearchParams(keyword: q, page: 1));
      if (!mounted) return;
      setState(() {
        _results = resp.data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
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

  // 多P歌单 → 收藏为合集（type=collection，曲目逐个入库）
  Future<void> _collectOrder(SearchItem item) async {
    try {
      final tracks = musicItemsToTracks(item.musicList ?? const []);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);

    return Scaffold(
      body: AuroraBackground(
        child: MiniBarPage(
          child: SafeArea(
            // 空态走覆盖层（Stack + Positioned.fill）：居中于可视区且不占列表流
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BackLink(),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (_) => _onChanged(),
                      style: TextStyle(fontSize: 14.5, color: t.fg),
                      decoration: InputDecoration(
                        hintText: "搜索歌曲 / 歌手 / 合集",
                        hintStyle: TextStyle(fontSize: 14, color: t.fgMute),
                        prefixIcon: Icon(Icons.search, size: 20, color: t.fgDim),
                        filled: true,
                        fillColor: t.surface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                    // 加载骨架留在列表流（贴搜索框下方）；空/失败/无结果走覆盖层
                    if (_controller.text.trim().isNotEmpty && _loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: SkeletonListView(rows: 5),
                      ),
                    for (final item in _results)
                      // 多P（musicList>1）→ 歌单行；单曲 → 歌曲行（musicList 首条带播放 id）
                      if ((item.musicList?.length ?? 0) > 1)
                        _OrderResultTile(
                          item: item,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlaylistDetailPage(
                                playlist: Playlist(
                                  id: "bili:${item.id}",
                                  name: item.name,
                                  type: PlaylistType.collection,
                                ),
                                tracks: musicItemsToTracks(item.musicList ?? const []),
                              ),
                            ),
                          ),
                          onCollect: () => _collectOrder(item),
                        )
                      else
                        SongListTile(
                          track: item.toTrack(),
                          onTap: () => _playTrack(item.toTrack()),
                          onMorePressed: () =>
                              AppToast.show(context, "加入歌单在 S4 接入"),
                        ),
                  ],
                ),
                // 空态覆盖：初始引导 / 搜索失败 / 无结果（按状态取一；加载与结果态不挂覆盖层）
                if (_controller.text.trim().isEmpty)
                  const Positioned.fill(
                    child: EmptyState(
                      emoji: "🔍",
                      title: "输入关键词开始搜索",
                      subtitle: "支持 B 站 / 酷我音源",
                    ),
                  )
                else if (!_loading && _results.isEmpty)
                  Positioned.fill(
                    child: _error != null
                        ? EmptyState(
                            emoji: "⚠️",
                            title: "搜索失败",
                            subtitle: "检查网络后重试",
                            action: GlassChip(
                              label: "重试",
                              onTap: () => _search(_query),
                            ),
                          )
                        : EmptyState(
                            emoji: "🎵",
                            title: "没有找到与“$_query”相关的内容",
                            subtitle: "换个关键词试试",
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

/// 多P歌单结果行：封面 + 标题 + 收藏动作
class _OrderResultTile extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onTap;
  final VoidCallback onCollect;

  const _OrderResultTile({
    required this.item,
    required this.onTap,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
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
                  Text(
                    "多P 歌单 · ${item.author}",
                    style: TextStyle(fontSize: 12, color: t.fgDim),
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
          ],
        ),
      ),
    );
  }
}
