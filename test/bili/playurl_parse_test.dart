import "package:bobomusic/origin_sdk/bili/bili_api.dart";
import "package:bobomusic/origin_sdk/bili/bili_api_error.dart";
import "package:flutter_test/flutter_test.dart";

/// playurl 解析与 LRU 缓存特征测试（S2.3）
void main() {
  group("parsePlayUrl", () {
    test("dash 多音频按 bandwidth 取最高", () {
      final musicUrl = parsePlayUrl({
        "dash": {
          "audio": [
            {"baseUrl": "https://low.example/a.m4s", "bandwidth": 64000},
            {"baseUrl": "https://high.example/a.m4s", "bandwidth": 320000},
            {"baseUrl": "https://mid.example/a.m4s", "bandwidth": 128000},
          ],
        },
      });
      expect(musicUrl.url, "https://high.example/a.m4s");
      // 取流直链必须带 Referer（缺省 403）
      expect(musicUrl.headers?["Referer"], "https://www.bilibili.com/");
    });

    test("dash.audio 为空 → BiliParseError（接口漂移先红）", () {
      expect(
        () => parsePlayUrl({"dash": {"audio": []}}),
        throwsA(isA<BiliParseError>()),
      );
      expect(
        () => parsePlayUrl({}),
        throwsA(isA<BiliParseError>()),
      );
    });
  });

  group("TtlLruCache", () {
    var now = DateTime(2026, 1, 1, 12);
    final cache = TtlLruCache<String>(
      maxEntries: 3,
      ttl: const Duration(minutes: 5),
      now: () => now,
    );

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      cache.clear();
    });

    test("TTL 过期后返回 null", () {
      cache.set("k", "v");
      now = now.add(const Duration(minutes: 5, seconds: 1));
      expect(cache.get("k"), isNull);
    });

    test("TTL 内命中，且触摸续命（LRU）", () {
      cache.set("a", "1");
      cache.set("b", "2");
      cache.set("c", "3");
      cache.get("a"); // 触摸 a → 变为最近使用
      cache.set("d", "4"); // 容量 3：应淘汰未被触摸的 b
      now = now.add(const Duration(minutes: 3));
      expect(cache.get("a"), "1");
      expect(cache.get("b"), isNull);
      expect(cache.get("c"), "3");
      expect(cache.get("d"), "4");
    });

    test("超容量淘汰最早写入项", () {
      cache.set("a", "1");
      cache.set("b", "2");
      cache.set("c", "3");
      cache.set("d", "4");
      expect(cache.get("a"), isNull);
      expect(cache.get("d"), "4");
    });
  });

  test("getMusicUrl：缺 cid 直接抛 BiliInvalidIdError（不发网络请求）", () {
    // BiliId "aid_bvid" 无 cid；构造即抛，不触达鉴权与网络
    final api = BiliApi();
    expect(
      () => api.getMusicUrl("123_BVabc"),
      throwsA(isA<BiliInvalidIdError>()),
    );
  });
}
