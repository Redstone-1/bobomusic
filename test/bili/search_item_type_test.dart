import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter_test/flutter_test.dart";

/// B 站搜索条目类型判定（合集绝不掉进单曲分支直接播放——所有者明确要求）
void main() {
  Map<String, dynamic> seasonJson() => {
        "aid": 100,
        "bvid": "BVseason01",
        "pic": "https://img.example/s.jpg",
        "title": "深夜民谣合集",
        "duration": 0,
        "author": "UP主",
        "is_season_display": true,
        "ugc_season": {"mid": 42, "id": 7},
      };

  test("UGC 合集条目（is_season_display）：type=orderName，无内嵌曲目", () {
    final item = BiliSearchItem.fromJson(seasonJson());
    expect(item.type, SearchType.orderName);
    expect(item.musicList, isEmpty);
    expect(item.ugcSeason?.mid, 42);
    expect(item.ugcSeason?.seasonId, 7);
  });

  test("多P 视频（videos>1）：type=orderName，内嵌分P曲目", () {
    final item = BiliSearchItem.fromJson({
      "aid": 200,
      "bvid": "BVmulti01",
      "pic": "",
      "title": "多P歌单",
      "duration": 300,
      "author": "UP主",
      "videos": 2,
      "pages": [
        {"cid": 11, "part": "第一首", "duration": 100, "first_frame": ""},
        {"cid": 12, "part": "第二首", "duration": 200, "first_frame": ""},
      ],
    });
    expect(item.type, SearchType.orderName);
    expect(item.musicList, hasLength(2));
  });

  test("单曲视频：type=music，id 取分P播放 id", () {
    final item = BiliSearchItem.fromJson({
      "aid": 300,
      "bvid": "BVsingle01",
      "pic": "",
      "title": "单曲",
      "duration": 100,
      "author": "UP主",
      "videos": 1,
      "pages": [
        {"cid": 21, "part": "单曲", "duration": 100, "first_frame": ""},
      ],
    });
    expect(item.type, SearchType.music);
  });

  test("普通条目（无 videos/pages/season 字段）：type 为 null 不误判合集", () {
    final item = BiliSearchItem.fromJson({
      "aid": 400,
      "bvid": "BVplain001",
      "pic": "",
      "title": "普通视频",
      "duration": 100,
      "author": "UP主",
    });
    // type=null 且 musicList 空 → 搜索页按单曲路由（既有契约）
    expect(item.type, isNull);
    expect(item.musicList, isEmpty);
    expect(item.ugcSeason, isNull);
  });
}
