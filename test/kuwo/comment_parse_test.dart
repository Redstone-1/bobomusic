import "package:bobomusic/origin_sdk/kuwo/kuwo_api.dart";
import "package:flutter_test/flutter_test.dart";

/// 酷我评论解析（纯函数，特征锁定；响应形状为 2026-10-31 匿名实测口径）：
/// 数字多为字符串，msg 含 HTML 实体/标签需 decodeKuwoText 清洗，
/// reply 为被回复旧评论（同构嵌套），hasMore 按 page/totalPage 推算
void main() {
  test("rows 平铺字段解析 + 分页推算", () {
    final page = parseKuwoComments({
      "result": "ok",
      "total": "1222",
      "totalPage": "62",
      "rows": [
        {
          "id": "9001",
          "u_name": "酷我用户",
          "u_pic": "http://img.kuwo.cn/u.jpg",
          "msg": "好听&amp;点赞",
          "like_num": "66",
          "time": "2026-10-31 12:00:00",
        },
        {
          "id": "9002",
          "u_name": "回复者",
          "msg": "回复内容",
          "like_num": 0,
          "time": "2026-10-31 13:00:00",
          "reply": {
            "u_name": "楼主",
            "msg": "被回复内容",
            "u_pic": "http://img.kuwo.cn/lz.jpg",
          },
        },
      ],
    }, page: 1);

    expect(page.total, 1222);
    expect(page.hasMore, isTrue);
    expect(page.items, hasLength(2));
    expect(page.items.first.content, "好听&点赞");
    expect(page.items.first.userName, "酷我用户");
    // 头像统一切 https：安卓默认拦 cleartext，http 图会全部落到占位块
    expect(page.items.first.avatarUrl, "https://img.kuwo.cn/u.jpg");
    expect(page.items.first.likedCount, 66);
    expect(page.items.first.timeLabel, "2026-10-31 12:00:00");
    expect(page.items.first.isHot, isFalse);
    expect(page.items.last.replyTo, "被回复内容");
    expect(page.items.last.replyToUser, "楼主");
    expect(page.items.last.replyToAvatarUrl, "https://img.kuwo.cn/lz.jpg");
  });

  test("末页 hasMore=false，脏数据跳过，msg 标签清洗", () {
    final page = parseKuwoComments({
      "total": "1",
      "totalPage": "1",
      "rows": [
        {"id": "1", "msg": "<b>带标签</b>"},
        {"id": "2", "msg": ""},
      ],
    }, page: 1);

    expect(page.hasMore, isFalse);
    expect(page.items, hasLength(1));
    expect(page.items.single.content, "带标签");
  });
}
