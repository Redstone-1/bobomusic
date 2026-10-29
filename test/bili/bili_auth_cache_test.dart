import "package:bobomusic/origin_sdk/bili/bili_auth.dart";
import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../helpers/http_adapter.dart";

Map<String, Object> cached(DateTime now, {String version = "4"}) => {
      "bili_cache_version": version,
      "bili_catch_created_at": now.millisecondsSinceEpoch,
      "bili_sign_img_key": "img123",
      "bili_sign_sub_key": "sub456",
      "bili_spi_b3": "old-b3",
      "bili_spi_b4": "old-b4",
      "bili_ticket": "old-ticket",
      "bili_b_nut": "old-nut",
      "bili_buvid3": "home-b3",
      "bili_b_nut_created_at": now.millisecondsSinceEpoch,
    };

StubHttpAdapter bootstrap({bool rejectHome = false}) =>
    StubHttpAdapter((options) {
      switch (options.uri.path) {
        case "/":
          if (rejectHome) return jsonBody({}, status: 503);
          return ResponseBody.fromString("", 200, headers: {
            "set-cookie": [
              "b_nut=new-nut; Path=/",
              "buvid3=new-home-b3; Path=/"
            ],
          });
        case "/x/web-interface/nav":
          return jsonBody({
            "code": -101,
            "data": {
              "wbi_img": {
                "img_url":
                    "https://example/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png",
                "sub_url":
                    "https://example/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png",
              }
            },
          });
        case "/x/frontend/finger/spi":
          return jsonBody({
            "code": 0,
            "data": {"b_3": "new-spi-b3", "b_4": "new-b4"}
          });
        default:
          return jsonBody({
            "code": 0,
            "data": {"ticket": "new-ticket"}
          });
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("有效缓存还原不触网，会话达到 24 小时后重新获取材料", () async {
    var now = DateTime(2026, 10, 29, 10);
    SharedPreferences.setMockInitialValues(cached(now));
    final adapter = bootstrap();
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = BiliAuth(dio: dio, now: () => now);
    await auth.ensure();
    expect(adapter.requests, isEmpty);
    expect(auth.signData!.imgKey, "img123");
    expect(auth.spiData!.b3, "home-b3");
    now = now.add(const Duration(hours: 24));
    await auth.ensure();
    expect(adapter.requests.length, 4);
    expect(auth.ticket, "new-ticket");
    expect(auth.bNut, "new-nut");
    expect(auth.spiData!.b3, "new-home-b3");
    dio.close();
  });

  test("并发重刷只取一组材料，跳过有效但已被风控拒绝的持久缓存", () async {
    final now = DateTime(2026, 10, 29, 10);
    SharedPreferences.setMockInitialValues(cached(now));
    final adapter = bootstrap();
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = BiliAuth(dio: dio, now: () => now);
    await auth.ensure();
    await Future.wait([auth.refresh(), auth.refresh(), auth.ensure()]);
    expect(adapter.requests.length, 4);
    expect(auth.ticket, "new-ticket");
    expect(auth.cookieHeader(), contains("new-nut"));
    dio.close();
  });

  test("缓存版本不匹配时重刷；主页失败仍可用 spi 完成鉴权", () async {
    final now = DateTime(2026, 10, 29, 10);
    SharedPreferences.setMockInitialValues(
        cached(now, version: "3")..remove("bili_b_nut_created_at"));
    final adapter = bootstrap(rejectHome: true);
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = BiliAuth(dio: dio, now: () => now);
    await auth.ensure();
    expect(auth.ticket, "new-ticket");
    expect(auth.spiData!.b3, "new-spi-b3");
    expect(auth.cookieHeader(), isNot(contains("b_nut=")));
    dio.close();
  });

  test("cookie 省略空值，非空值保持传递", () {
    final auth = BiliAuth()
      ..spiData = const SpiData(b3: "b3", b4: "b4")
      ..ticket = "tk"
      ..bNut = "";
    expect(auth.cookieHeader(), contains("buvid3=b3"));
    expect(auth.cookieHeader(), contains("bili_ticket=tk"));
    expect(auth.cookieHeader(), isNot(contains("b_nut=")));
    auth.bNut = "nut";
    expect(auth.cookieHeader(), contains("b_nut=nut"));
  });
}
