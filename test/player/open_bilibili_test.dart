import "package:bobomusic/features/player/open_bilibili.dart";
import "package:flutter_test/flutter_test.dart";

/// 去 B 站看视频：id → bvid 纯函数（B 站 id 约定 aid_bvid[_cid]）
void main() {
  test("带 cid / 不带 cid 都能取 bvid", () {
    expect(bilibiliBvid("123_BV1xx411c7mD_456"), "BV1xx411c7mD");
    expect(bilibiliBvid("123_BV1xx411c7mD"), "BV1xx411c7mD");
  });

  test("非法 id 返回 null", () {
    expect(bilibiliBvid("abc"), isNull);
    expect(bilibiliBvid("123_"), isNull);
    expect(bilibiliBvid(""), isNull);
  });
}
