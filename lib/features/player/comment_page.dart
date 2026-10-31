import "package:flutter/material.dart";

import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/app_buttons.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../origin_sdk/origin_types.dart" hide OriginType;

/// 歌曲评论页（仅查看）：网易/酷我源开放入口（其它音源无评论数据源）。
/// 上拉翻页按需加载（距底 400px 预取，与搜索页同款），整页失败可重试；
/// 网易首页热评独立分区，酷我无热门分区
class CommentPage extends StatefulWidget {
  final Track track;

  const CommentPage({super.key, required this.track});

  static void open(BuildContext context, Track track) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CommentPage(track: track)),
    );
  }

  @override
  State<CommentPage> createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage> {
  static const _pageSize = 20;

  /// 热门评论（网易首页 hotComments；酷我恒空）
  List<CommentItem> _hot = const [];
  List<CommentItem> _items = [];
  int _total = 0;
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<CommentsPage> _fetch(int page) {
    // 评论仅网易/酷我开放入口（其它音源无评论数据源，默认实现抛 UnsupportedError）
    return _activeApi.fetchComments(
      widget.track.id,
      page: page,
      rows: _pageSize,
    );
  }

  OriginService get _activeApi => widget.track.origin == OriginType.netease
      ? neteaseApi
      : kuwoApi;

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _hot = [for (final c in resp.items) if (c.isHot) c];
        _items = [for (final c in resp.items) if (!c.isHot) c];
        _total = resp.total;
        _page = 1;
        _hasMore = resp.hasMore;
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

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final resp = await _fetch(_page + 1);
      if (!mounted) return;
      final seen = {
        for (final c in _hot) c.id,
        for (final c in _items) c.id,
      };
      final fresh = <CommentItem>[];
      for (final c in resp.items) {
        if (c.id.isNotEmpty && !seen.add(c.id)) continue;
        fresh.add(c);
      }
      setState(() {
        _items = [..._items, ...fresh];
        _page++;
        _hasMore = resp.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      AppToast.show(context, "评论加载失败，上滑重试");
    }
  }

  String _formatCount(int count) => count >= 10000
      ? "${(count / 10000).toStringAsFixed(1)}万"
      : "$count";

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BackLink(),
                    ),
                    PageHeader(
                      title: _total > 0 ? "评论 ${_formatCount(_total)}" : "评论",
                      subtitle: widget.track.effectiveName,
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(context, t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AuroraTokens t) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2.4, color: t.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: EmptyState(
          compact: true,
          emoji: "⚠️",
          title: "评论加载失败",
          subtitle: "$_error",
          action: GlassChip(label: "重试", onTap: _reload),
        ),
      );
    }
    if (_hot.isEmpty && _items.isEmpty) {
      return Center(
        child: EmptyState(
          asset: "assets/illustrations/empty_music.svg",
          title: "暂无评论",
          subtitle: "这首歌还没有人留下评论",
        ),
      );
    }
    final showSections = _hot.isNotEmpty;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // 触底前 400px 预取下一页（仅纵向列表）
        if (n.metrics.axis == Axis.vertical &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _loadMore();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 110),
        children: [
          if (showSections) ...[
            SectionHeader(title: "热门评论"),
            for (final (i, comment) in _hot.indexed)
              _CommentTile(comment: comment, isLast: i == _hot.length - 1),
            SectionHeader(title: "最新评论"),
          ],
          for (final (i, comment) in _items.indexed)
            _CommentTile(comment: comment, isLast: i == _items.length - 1),
          // 翻页态：细进度圈或到底提示
          if (_loadingMore)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.fgMute,
                  ),
                ),
              ),
            )
          else if (!_hasMore && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Text(
                  "到底了",
                  style: TextStyle(fontSize: 12, color: t.fgMute),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单条评论：头像 + 头部行（昵称/热门标记/点赞）+ 时间 + 引用条 + 正文。
/// 引用用主题色左条 + @昵称高亮和正文拉开层级；条目间发丝线分隔
class _CommentTile extends StatelessWidget {
  final CommentItem comment;
  final bool isLast;

  const _CommentTile({required this.comment, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.hairline, width: 0.5),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAvatar(url: comment.avatarUrl, name: comment.userName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部行：昵称 + 热门标记 + 点赞（昵称 Expanded 吃满剩余宽度，
                // 点赞始终右贴；Spacer 会把昵称截在半行）
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              comment.userName.isEmpty
                                  ? "匿名用户"
                                  : comment.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: t.fg,
                              ),
                            ),
                          ),
                          if (comment.isHot) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: t.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                "热",
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.favorite_border, size: 13, color: t.fgMute),
                    const SizedBox(width: 3),
                    // 0 赞不展示数字，留纯图标
                    Text(
                      comment.likedCount > 0 ? "${comment.likedCount}" : "",
                      style: TextStyle(fontSize: 11, color: t.fgMute),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (comment.timeLabel.isNotEmpty)
                  Text(
                    comment.timeLabel,
                    style: TextStyle(fontSize: 10.5, color: t.fgMute),
                  ),
                // 被回复引用 = 楼中楼式嵌套小评论（小头像 + 昵称 + 内容内嵌缩进），
                // 两层数据关系直接可见。源接口为扁平时间序（回复只内嵌父评论摘要，
                // 父评论常在后续页尚未加载），真树须全量拉取，违背按需翻页口径。
                // 布局只用文字自然撑高——不能用 Row(stretch)+空 Container 画条，
                // 无界高度下空盒被强制 h=Infinity（页面级联冻结）
                if (comment.replyTo.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(t.radiusSm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CommentAvatar(
                          url: comment.replyToAvatarUrl,
                          name: comment.replyToUser,
                          size: 18,
                          fontSize: 9,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (comment.replyToUser.isNotEmpty)
                                Text(
                                  comment.replyToUser,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.primary,
                                  ),
                                ),
                              Text(
                                comment.replyTo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: t.fgDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  comment.content,
                  style: TextStyle(fontSize: 14, height: 1.55, color: t.fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// 评论头像（主楼 36 / 楼中楼 18 共用）：
/// 加载中/失败都回退主题色系首字占位，不出现无主题色的白块
class _CommentAvatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;
  final double fontSize;

  const _CommentAvatar({
    required this.url,
    required this.name,
    this.size = 36,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final placeholder = Container(
      width: size,
      height: size,
      color: t.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? "友" : name.characters.first,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: t.primary,
        ),
      ),
    );
    if (url.isEmpty) return ClipOval(child: placeholder);
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
