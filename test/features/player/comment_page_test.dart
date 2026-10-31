import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/data/origin_service.dart";
import "package:bobomusic/data/models/track.dart";
import "package:bobomusic/features/player/comment_page.dart";
import "package:bobomusic/origin_sdk/origin_types.dart" hide OriginType;
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

/// 分页评论 Fake：按页返回，页数耗尽后 hasMore=false
class _PagedCommentApi extends Fake implements OriginService {
  final int pages;
  int fetches = 0;

  _PagedCommentApi({required this.pages});

  @override
  Future<CommentsPage> fetchComments(
    String songId, {
    int page = 1,
    int rows = 20,
  }) async {
    fetches++;
    if (page > pages) {
      return CommentsPage(items: const [], total: 0, hasMore: false);
    }
    return CommentsPage(
      items: [
        for (var i = 0; i < rows; i++)
          CommentItem(
            id: "p${page}_c$i",
            userName: "用户$page-$i",
            avatarUrl: "",
            content: "第 $page 页 第 $i 条评论内容，用来撑起足够的滚动高度。",
            replyTo: page == 1 && i == 0 ? "被回复的旧评论内容" : "",
            replyToUser: page == 1 && i == 0 ? "楼主" : "",
            replyToAvatarUrl: page == 1 && i == 0 ? "https://img.example/lz.jpg" : "",
            likedCount: i,
            timeLabel: "2026-11-01",
            isHot: page == 1 && i < 3,
          ),
      ],
      total: pages * rows,
      hasMore: page < pages,
    );
  }
}

const _kFirstContent = "第 1 页 第 0 条评论内容，用来撑起足够的滚动高度。";

void main() {
  testWidgets("评论页滚动到底：翻页加载后继续可滚动，不卡死", (tester) async {
    kuwoApi = _PagedCommentApi(pages: 3);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeColor.oceanBlue, Brightness.light),
        home: Scaffold(
          body: CommentPage(
            track: Track(
              id: "kuwo:1",
              name: "测试歌曲",
              author: "歌手",
              origin: OriginType.kuwo,
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // loading
    await tester.pump(); // 首页数据落地
    expect(find.text(_kFirstContent), findsOneWidget);

    // 连续拖到底：每次翻页追加 20 条，直到 hasMore=false 出现「到底了」
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      if (find.text("到底了").evaluate().isNotEmpty) break;
    }
    expect(find.text("到底了"), findsOneWidget);

    // 到底后继续拖：不得抛断言、页面仍可滚动（无异常即通过）
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  });
}
