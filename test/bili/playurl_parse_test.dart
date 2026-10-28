import "dart:convert";
import "dart:typed_data";

import "package:bobomusic/origin_sdk/bili/bili_api.dart";
import "package:bobomusic/origin_sdk/bili/bili_api_error.dart";
import "package:bobomusic/origin_sdk/bili/bili_auth.dart";
import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";

/// playurl 解析与 LRU 缓存特征测试（S2.3）
void main() {
  group("parsePlayUrl", () {
    test("dash 多音频按 bandwidth 取最高", () {
      final musicUrl = parsePlayUrl({
        "dash": {
          "audio": [
            {"baseUrl": "https://low.example/a.m4s", "bandwidth": 64000},
            {
              "baseUrl": "https://high.example/a.m4s",
              "bandwidth": 320000,
              "backupUrl": ["https://bak1.example/a.m4s", "https://bak2.example/a.m4s"],
            },
            {"baseUrl": "https://mid.example/a.m4s", "bandwidth": 128000},
          ],
        },
      });
      expect(musicUrl.url, "https://high.example/a.m4s");
      // 取流直链必须带 Referer（缺省 403）
      expect(musicUrl.headers?["Referer"], "https://www.bilibili.com/");
      // 备用直链保留首项（降级用，§5.3-4）
      expect(musicUrl.backupUrl, "https://bak1.example/a.m4s");
    });

    test("backupUrl 缺失时为 null（不抛错）", () {
      final musicUrl = parsePlayUrl({
        "dash": {
          "audio": [
            {"baseUrl": "https://only.example/a.m4s", "bandwidth": 320000},
          ],
        },
      });
      expect(musicUrl.backupUrl, isNull);
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

  test("getMusicUrl：缺 cid 且 view 也补不齐 → BiliInvalidIdError（不发网络请求外仍类型化）", () {
    // view 桩返回无 pages 的数据 → 自愈失败 → 类型化上抛
    final dio = Dio();
    dio.httpClientAdapter = _StubAdapter(
      (path) => _jsonBody({
        "code": 0,
        "data": {
          "aid": 123,
          "bvid": "BVabc",
          "cid": 777,
          "pic": "https://pic.example/a.jpg",
          "title": "歌",
          "author": "UP",
          "duration": 227,
        },
      }),
    );
    final api = _stubAuthApi(dio);
    expect(
      api.getMusicUrl("123_BVabc"),
      throwsA(isA<BiliInvalidIdError>()),
    );
  });

  test("getMusicUrl：缺 cid 自愈——view 补 cid 后正常出直链", () async {
    // 2026-10 实证：搜索响应不再带 pages，搜索/队列/旧库曲目无 cid。
    // 桩模拟 view（带 pages）+ playurl（dash），锁「view 补 cid → 取流」链路
    final dio = Dio();
    dio.httpClientAdapter = _StubAdapter((path) {
      if (path.endsWith("/view")) {
        return _jsonBody({
          "code": 0,
          "data": {
            "aid": 123,
            "bvid": "BVabc",
            "cid": 777,
            "pic": "https://pic.example/a.jpg",
            "title": "歌",
            "author": "UP",
            "duration": 227,
            "videos": 1,
            "pages": [
              {"cid": 777, "part": "正片", "duration": 227, "first_frame": ""},
            ],
          },
        });
      }
      return _jsonBody({
        "code": 0,
        "data": {
          "dash": {
            "audio": [
              {"baseUrl": "https://high.example/a.m4s", "bandwidth": 320000},
            ],
          },
        },
      });
    });
    final musicUrl = await _stubAuthApi(dio).getMusicUrl("123_BVabc");
    expect(musicUrl.url, "https://high.example/a.m4s");
  });
}

/// 按 path 分发的假适配器：view/playurl 响应全走桩，测试不触网
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(String path) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options.uri.path);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> json) => ResponseBody.fromString(
      jsonEncode(json),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 预置鉴权三件套（字段公开可注入，ensure 直接就绪不再发请求）；
/// wbi 密钥须各 32 位（getMixinKey 按 64 位混淆表取字符，短串会越界）
BiliApi _stubAuthApi(Dio dio) {
  final auth = BiliAuth();
  auth.signData = SignData(
    imgKey: "0123456789abcdef0123456789abcdef",
    subKey: "fedcba9876543210fedcba9876543210",
  );
  auth.spiData = SpiData(b3: "b3", b4: "b4");
  auth.ticket = "tk";
  return BiliApi(authOverride: auth, dioOverride: dio);
}
