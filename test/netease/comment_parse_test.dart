import "package:bobomusic/origin_sdk/netease/netease_api.dart";
import "package:flutter_test/flutter_test.dart";

/// 网易评论解析（纯函数，特征锁定；响应形状为 2026-10-31 匿名实测口径）：
/// 首页 hotComments + comments，more 字段决定翻页，脏数据跳过
void main() {
  test("首页：hotComments 置顶 + comments + total/more", () {
    final page = parseNeteaseComments({
      "code": 200,
      "total": 70425,
      "more": true,
      "hotComments": [
        {
          "commentId": 111,
          "content": "热评内容",
          "likedCount": 12345,
          "timeStr": "2014-10-20",
          "user": {"nickname": "热评用户", "avatarUrl": "https://a/p.jpg"},
        },
      ],
      "comments": [
        {
          "commentId": 222,
          "content": "最新内容",
          "likedCount": 3,
          "timeStr": "2026-10-31",
          "beReplied": [
            {
              "content": "被回复的旧评论",
              "user": {
                "nickname": "被回复用户",
                "avatarUrl": "https://p.example/r.jpg",
              },
            },
          ],
          "user": {"nickname": "最新用户", "avatarUrl": ""},
        },
      ],
    });

    expect(page.total, 70425);
    expect(page.hasMore, isTrue);
    expect(page.items, hasLength(2));
    expect(page.items.first.isHot, isTrue);
    expect(page.items.first.userName, "热评用户");
    expect(page.items.first.content, "热评内容");
    expect(page.items.first.likedCount, 12345);
    expect(page.items.first.timeLabel, "2014-10-20");
    expect(page.items.first.replyTo, isEmpty);
    expect(page.items.last.isHot, isFalse);
    expect(page.items.last.replyTo, "被回复的旧评论");
    expect(page.items.last.replyToUser, "被回复用户");
    expect(page.items.last.replyToAvatarUrl, "https://p.example/r.jpg");
  });

  test("脏数据：空内容跳过、user/likedCount 缺失回退空值", () {
    final page = parseNeteaseComments({
      "total": 2,
      "more": false,
      "comments": [
        {"commentId": 1, "content": "   "},
        {"commentId": 2, "content": "正常", "likedCount": null},
      ],
    });

    expect(page.hasMore, isFalse);
    expect(page.items, hasLength(1));
    expect(page.items.single.userName, "");
    expect(page.items.single.likedCount, 0);
  });
}
