import "package:bobomusic/origin_sdk/kuwo/kuwo_api.dart";
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/http_adapter.dart";

void main() {
  test("酷我优先申请最高 MP3 档位，成功后不再请求默认档位", () async {
    final adapter = StubHttpAdapter((options) {
      expect(options.queryParameters["br"], "320kmp3");
      return ResponseBody.fromString("https://cdn.example/high.mp3", 200);
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final result = await KuwoApi(dio: dio).getMusicUrl("kuwo:1");
    expect(result.url, "https://cdn.example/high.mp3");
    expect(result.contentType, "audio/mpeg");
    expect(adapter.requests.length, 1);
    dio.close();
  });

  test("最高档没有地址才回退现有默认取流，接口拒绝不循环降级", () async {
    final adapter = StubHttpAdapter((options) => ResponseBody.fromString(
        options.queryParameters["br"] == null
            ? "https://cdn.example/default.mp3"
            : "",
        200));
    final dio = Dio()..httpClientAdapter = adapter;
    expect((await KuwoApi(dio: dio).getMusicUrl("kuwo:1")).url,
        "https://cdn.example/default.mp3");
    expect(adapter.requests.length, 2);
    dio.close();

    final limited = StubHttpAdapter((_) => ResponseBody.fromString("", 429));
    final rejected = Dio()..httpClientAdapter = limited;
    await expectLater(KuwoApi(dio: rejected).getMusicUrl("kuwo:1"),
        throwsA(isA<KuwoApiError>()));
    expect(limited.requests.length, 1);
    rejected.close();
  });
}
