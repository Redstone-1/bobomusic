import "package:bobomusic/origin_sdk/bili/bili_api.dart";
import "package:bobomusic/origin_sdk/bili/bili_api_error.dart";
import "package:bobomusic/origin_sdk/bili/bili_auth.dart";
import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/http_adapter.dart";

class ReadyAuth extends BiliAuth {
  int refreshes = 0;
  ReadyAuth() {
    signData = const SignData(
      imgKey: "0123456789abcdef0123456789abcdef",
      subKey: "fedcba9876543210fedcba9876543210",
    );
    spiData = const SpiData(b3: "b3", b4: "b4");
    ticket = "ticket";
  }
  @override
  Future<void> ensure() async {}
  @override
  Future<void> refresh() async {
    refreshes++;
    signData = const SignData(
      imgKey: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      subKey: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    );
  }
}

Map<String, Object> searchResult() => {
      "code": 0,
      "data": {"page": 1, "numResults": 0, "pagesize": 20, "result": []},
    };

void main() {
  test("code=0 voucher：重刷后重新签名，恢复正常搜索", () async {
    final auth = ReadyAuth();
    final adapter = StubHttpAdapter((options) {
      if (auth.refreshes == 0) {
        return jsonBody({
          "code": 0,
          "data": {"v_voucher": "risk"}
        });
      }
      return jsonBody(searchResult());
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final api = BiliApi(authOverride: auth, dioOverride: dio);
    final result = await api.search(const SearchParams(keyword: "歌", page: 1));
    expect(result.data, isEmpty);
    expect(auth.refreshes, 1);
    expect(adapter.requests.length, 2);
    expect(adapter.requests[0].queryParameters["w_rid"],
        isNot(adapter.requests[1].queryParameters["w_rid"]));
    dio.close();
  });

  test("风控持续存在：只重试一次并返回类型化错误", () async {
    final auth = ReadyAuth();
    final adapter = StubHttpAdapter((_) => jsonBody({
          "code": 0,
          "data": {"v_voucher": "risk"}
        }));
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
      BiliApi(authOverride: auth, dioOverride: dio)
          .search(const SearchParams(keyword: "歌", page: 1)),
      throwsA(isA<BiliApiRejectError>()
          .having((e) => e.riskControl, "riskControl", isTrue)),
    );
    expect(auth.refreshes, 1);
    expect(adapter.requests.length, 2);
    dio.close();
  });

  test("普通业务错误不刷新，响应漂移仍归一为解析错误", () async {
    final auth = ReadyAuth();
    final dio = Dio();
    final rejected =
        StubHttpAdapter((_) => jsonBody({"code": -404, "message": "视频不存在"}));
    dio.httpClientAdapter = rejected;
    final api = BiliApi(authOverride: auth, dioOverride: dio);
    await expectLater(
        api.searchDetail("123_BVfake"), throwsA(isA<BiliApiRejectError>()));
    expect(auth.refreshes, 0);
    expect(rejected.requests.length, 1);
    dio.httpClientAdapter =
        StubHttpAdapter((_) => jsonBody({"code": 0, "data": {}}));
    await expectLater(api.search(const SearchParams(keyword: "歌", page: 1)),
        throwsA(isA<BiliParseError>()));
    dio.close();
  });

  test("取流重试仍不带 cookie；失败后显式刷新可绕过旧直链缓存", () async {
    final auth = ReadyAuth();
    var calls = 0;
    final adapter = StubHttpAdapter((options) {
      calls++;
      expect(options.headers.keys.any((key) => key.toLowerCase() == "cookie"),
          isFalse);
      if (calls == 1) {
        return jsonBody({"code": -403, "message": "签名已失效"});
      }
      return jsonBody({
        "code": 0,
        "data": {
          "dash": {
            "audio": [
              {"baseUrl": "https://cdn.example/$calls", "bandwidth": 100},
            ]
          }
        },
      });
    });
    final dio = Dio()..httpClientAdapter = adapter;
    dio.options.headers["Cookie"] = "stale";
    final api = BiliApi(authOverride: auth, dioOverride: dio);
    final first = await api.getMusicUrl("123_BVfake_777");
    expect(first.url, "https://cdn.example/2");
    expect((await api.getMusicUrl("123_BVfake_777")).url, first.url);
    expect(calls, 2);
    expect((await api.getMusicUrl("123_BVfake_777", forceRefresh: true)).url,
        "https://cdn.example/3");
    expect(auth.refreshes, 1);
    dio.close();
  });

  test("HTTP 412 重刷一次，429 保留状态码且不重试", () async {
    final auth = ReadyAuth();
    final adapter = StubHttpAdapter((_) => auth.refreshes == 0
        ? jsonBody({}, status: 412)
        : jsonBody(searchResult()));
    final recovered = Dio()..httpClientAdapter = adapter;
    await BiliApi(authOverride: auth, dioOverride: recovered)
        .search(const SearchParams(keyword: "歌", page: 1));
    expect(auth.refreshes, 1);
    expect(adapter.requests.length, 2);
    recovered.close();
    final dio = Dio()
      ..httpClientAdapter =
          StubHttpAdapter((_) => jsonBody({"message": "limited"}, status: 429));
    await expectLater(
      BiliApi(authOverride: ReadyAuth(), dioOverride: dio)
          .search(const SearchParams(keyword: "歌", page: 1)),
      throwsA(isA<BiliHttpError>().having((e) => e.statusCode, "status", 429)),
    );
    dio.close();
  });

  test("强制刷新失败后不再复用此前失效地址", () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = StubHttpAdapter((_) {
        calls++;
        if (calls == 2) return jsonBody({"code": -404, "message": "无地址"});
        return jsonBody({
          "code": 0,
          "data": {
            "dash": {
              "audio": [
                {"baseUrl": "https://cdn.example/$calls", "bandwidth": 100},
              ]
            }
          }
        });
      });
    final api = BiliApi(authOverride: ReadyAuth(), dioOverride: dio);
    await api.getMusicUrl("123_BVfake_777");
    await expectLater(api.getMusicUrl("123_BVfake_777", forceRefresh: true),
        throwsA(isA<BiliApiRejectError>()));
    expect(
        (await api.getMusicUrl("123_BVfake_777")).url, "https://cdn.example/3");
    dio.close();
  });
}
