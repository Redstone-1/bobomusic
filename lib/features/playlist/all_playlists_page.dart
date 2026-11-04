import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/app_search_field.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../data/models/playlist.dart";
import "../player/mini_player_bar.dart";
import "playlist_commands.dart" as commands;
import "playlist_tile.dart";
import "playlists_provider.dart";

/// 全量目录按需构建条目，搜索仅改变展示，不改变歌单原有排序。
class AllPlaylistsPage extends ConsumerStatefulWidget {
  const AllPlaylistsPage({super.key});

  @override
  ConsumerState<AllPlaylistsPage> createState() => _AllPlaylistsPageState();
}

class _AllPlaylistsPageState extends ConsumerState<AllPlaylistsPage> {
  final _searchController = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(playlistsProvider);
    final desktop = DesktopContent.of(context);
    final all = data.value;
    final query = _query.trim().toLowerCase();
    final visible =
        all?.where((p) => p.name.toLowerCase().contains(query)).toList();
    return Scaffold(
        body: AuroraBackground(
            child: MiniBarPage(
                child: SafeArea(
      child: CustomScrollView(key: const Key("all_playlists_scroll"), slivers: [
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BackLink(),
                    PageHeader(
                        title: "全部歌单",
                        subtitle: "共 ${all?.length ?? 0} 个自定义歌单",
                        trailing: GlassIconButton(
                            icon: const Icon(Icons.add),
                            onTap: () =>
                                commands.createPlaylist(context, ref))),
                    const SizedBox(height: 12),
                    AppSearchField(
                        fieldKey: const Key("all_playlists_search"),
                        controller: _searchController,
                        hintText: "搜索歌单名称",
                        onChanged: (value) => setState(() => _query = value)),
                  ]),
            )),
        if (all == null)
          SliverToBoxAdapter(
              child: data.hasError
                  ? EmptyState(
                      title: "歌单加载失败",
                      action: TextButton(
                          onPressed: () => ref.invalidate(playlistsProvider),
                          child: const Text("重试")))
                  : const Center(child: CircularProgressIndicator()))
        else if (visible!.isEmpty)
          SliverToBoxAdapter(
              child: EmptyState(
                  title: all.isEmpty ? "还没有歌单" : "没有找到相关歌单",
                  subtitle: all.isEmpty ? "点右上角 + 创建第一个歌单" : "换个名称试试"))
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: desktop
                ? SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisExtent: 240,
                            crossAxisSpacing: 18,
                            mainAxisSpacing: 20),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _tile(visible[index]))
                : SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _tile(visible[index])),
          ),
        SliverToBoxAdapter(child: SizedBox(height: desktop ? 30 : 140)),
      ]),
    ))));
  }

  Widget _tile(Playlist playlist) => PlaylistTile(
      name: playlist.name,
      count: playlist.count,
      cover: playlist.cover,
      onTap: () => commands.openPlaylist(context, ref, playlist),
      onMorePressed: () =>
          commands.showPlaylistActions(context, ref, playlist));
}
