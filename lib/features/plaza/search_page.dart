import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/mock/mock_data.dart";
import "../../data/models/track.dart";
import "../player/player_card_page.dart";

/// 搜索页（对齐原型 renderSub/search；S1 为 mock 过滤，S3 接 origin_sdk 真搜索）
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 按歌名/歌手过滤 mock 数据（不区分大小写）
  List<Track> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return mockTracks
        .where(
          (t) =>
              t.name.toLowerCase().contains(q) ||
              t.author.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final results = _results;

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const Align(alignment: Alignment.centerLeft, child: BackLink()),
              const SizedBox(height: 4),
              // 搜索框：玻璃风格，进入自动聚焦
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
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
              if (_query.trim().isEmpty)
                const EmptyState(
                  emoji: "🔍",
                  title: "输入关键词开始搜索",
                  subtitle: "支持 B 站 / 酷我音源",
                )
              else if (results.isEmpty)
                EmptyState(
                  emoji: "🎵",
                  title: "没有找到与“$_query”相关的内容",
                  subtitle: "换个关键词试试",
                )
              else ...[
                SectionHeader(title: "搜索结果", trailing: "${results.length} 首"),
                for (final track in results)
                  SongListTile(
                    track: track,
                    onTap: () => PlayerCardPage.start(context, ref, track),
                    onMorePressed: () {},
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
