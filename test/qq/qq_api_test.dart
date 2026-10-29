import "dart:convert";

import "package:bobomusic/origin_sdk/qq/qq_api.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/http_adapter.dart";

Map<String, dynamic> song(String mid, {bool vip = false, String? media}) => {
      "mid": mid,
      "name": "歌曲$mid",
      "interval": 200,
      "pay": {"pay_play": vip ? 1 : 0},
      if (media != null) "file": {"media_mid": media},
    };
Map<String, dynamic> page(List songs, {int total = 90}) => {
      "code": 0,
      "req_1": {
        "code": 0,
        "data": {
          "body": {
            "song": {"list": songs}
          },
          "meta": {"sum": total},
        }
      },
    };
Map<String, dynamic> vkey({String purl = "", int result = 0}) => {
      "code": 0,
      "req_0": {
        "code": 0,
        "data": {
          "midurlinfo": [
            {"purl": purl, "result": result}
          ],
          "sip": ["https://primary.example/", "https://backup.example/"],
        }
      },
    };

void main() {
  test("最高音质可用时只请求 M800，不额外探测较低档位", () async {
    final adapter = StubHttpAdapter((options) {
      final body = jsonDecode(options.queryParameters["data"] as String);
      expect(body["req_0"]["param"]["filename"], ["M800free.mp3"]);
      return jsonBody(vkey(purl: "M800free.mp3?vkey=sample"));
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final result = await QqApi(dio: dio).getMusicUrl("qq:free");
    expect(result.url, contains("M800free.mp3"));
    expect(adapter.requests.length, 1);
    dio.close();
  });

  test("免费曲目 320k 不可用时降到 128k，保留备链", () async {
    final filenames = <String>[];
    final adapter = StubHttpAdapter((options) {
      final data = jsonDecode(options.queryParameters["data"] as String);
      final filename = data["req_0"]["param"]["filename"][0] as String;
      filenames.add(filename);
      return jsonBody(filename.startsWith("M800")
          ? vkey(result: 104003)
          : vkey(purl: "M500free.mp3?vkey=sample"));
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final result = await QqApi(dio: dio).getMusicUrl("qq:free");
    expect(filenames, ["M800free.mp3", "M500free.mp3"]);
    expect(result.url, "https://primary.example/M500free.mp3?vkey=sample");
    expect(result.backupUrl, "https://backup.example/M500free.mp3?vkey=sample");
    expect(result.contentType, "audio/mpeg");
    dio.close();
  });

  test("MP3 两档都为空时尝试 AAC，并声明正确 MIME", () async {
    final filenames = <String>[];
    final dio = Dio()
      ..httpClientAdapter = StubHttpAdapter((options) {
        final body = jsonDecode(options.queryParameters["data"] as String);
        final filename = body["req_0"]["param"]["filename"][0] as String;
        filenames.add(filename);
        return jsonBody(
            vkey(purl: filename.startsWith("C400") ? "free.m4a" : ""));
      });
    final result = await QqApi(dio: dio).getMusicUrl("qq:free");
    expect(filenames, ["M800free.mp3", "M500free.mp3", "C400free.m4a"]);
    expect(result.contentType, "audio/mp4");
    dio.close();
  });

  test("空地址耗尽音质后给中性错误，不断言一定要 VIP", () async {
    final adapter = StubHttpAdapter((_) => jsonBody(vkey(result: 104003)));
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
        QqApi(dio: dio).getMusicUrl("qq:free"),
        throwsA(isA<QqApiError>()
            .having((e) => e.kind, "kind", QqFailure.unavailable)
            .having((e) => e.message.contains("VIP"), "不误报 VIP", isFalse)));
    expect(adapter.requests.length, 3);
    dio.close();
  });

  test("接口风控 2001 不当作音质缺失反复请求", () async {
    final adapter = StubHttpAdapter((_) => jsonBody({
          "code": 0,
          "req_0": {"code": 2001}
        }));
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
        QqApi(dio: dio).getMusicUrl("qq:free"),
        throwsA(isA<QqApiError>()
            .having((e) => e.kind, "kind", QqFailure.rejected)
            .having((e) => e.code, "code", 2001)));
    expect(adapter.requests.length, 1);
    dio.close();
  });

  test("HTTP 限流属于服务拒绝，不误报网络断开", () async {
    final adapter = StubHttpAdapter((_) => jsonBody({}, status: 429));
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
        QqApi(dio: dio).getMusicUrl("qq:free"),
        throwsA(isA<QqApiError>()
            .having((e) => e.kind, "kind", QqFailure.rejected)
            .having((e) => e.code, "code", 429)));
    expect(adapter.requests.length, 1);
    dio.close();
  });

  test("搜索服务错误、网络故障、响应格式变化分别识别", () async {
    for (final kind in [
      QqFailure.rejected,
      QqFailure.network,
      QqFailure.invalidResponse
    ]) {
      final dio = Dio()
        ..httpClientAdapter = StubHttpAdapter((options) {
          if (kind == QqFailure.network) {
            throw DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError);
          }
          return kind == QqFailure.rejected
              ? jsonBody({
                  "code": 0,
                  "req_1": {"code": 2001}
                })
              : jsonBody({
                  "code": 0,
                  "req_1": {"code": 0, "data": {}}
                });
        });
      await expectLater(
          QqApi(dio: dio).search(const SearchParams(keyword: "歌", page: 1)),
          throwsA(isA<QqApiError>().having((e) => e.kind, "kind", kind)));
      dio.close();
    }
  });

  test("前页全 VIP 会补查下一页，返回最后消费页码和 media_mid", () async {
    final pages = <int>[];
    String? filename;
    final dio = Dio()
      ..httpClientAdapter = StubHttpAdapter((options) {
        final body = jsonDecode(options.queryParameters["data"] as String);
        if (body["req_1"] != null) {
          final current = body["req_1"]["param"]["page_num"] as int;
          pages.add(current);
          return jsonBody(page(
            current == 1
                ? [song("vip", vip: true)]
                : [song("free", media: "media")],
          ));
        }
        filename = body["req_0"]["param"]["filename"][0] as String;
        return jsonBody(vkey(purl: "audio.mp3"));
      });
    final api = QqApi(dio: dio);
    final result = await api.search(const SearchParams(keyword: "歌", page: 1));
    expect(pages, [1, 2]);
    expect(result.current, 2);
    expect(result.hasMore, isTrue);
    expect(result.data.single.id, "qq:free");
    await api.getMusicUrl(result.data.single.id);
    expect(filename, "M800media.mp3");
    dio.close();
  });

  test("连续三页过滤空结果后保留下一页，不无限扫描", () async {
    final pages = <int>[];
    final dio = Dio()
      ..httpClientAdapter = StubHttpAdapter((options) {
        final body = jsonDecode(options.queryParameters["data"] as String);
        final current = body["req_1"]["param"]["page_num"] as int;
        pages.add(current);
        return jsonBody(page([song("vip", vip: true)], total: 300));
      });
    final api = QqApi(dio: dio);
    final first = await api.search(const SearchParams(keyword: "歌", page: 1));
    expect(first.data, isEmpty);
    expect(first.current, 3);
    expect(first.hasMore, isTrue);
    expect(pages, [1, 2, 3]);
    final next =
        await api.search(SearchParams(keyword: "歌", page: first.current + 1));
    expect(next.current, 6);
    expect(pages, [1, 2, 3, 4, 5, 6]);
    dio.close();
  });

  test("原始结果耗尽才终止，包括无总数的真实空页", () async {
    final adapter = StubHttpAdapter((_) => jsonBody(page([], total: 0)));
    final dio = Dio()..httpClientAdapter = adapter;
    final result =
        await QqApi(dio: dio).search(const SearchParams(keyword: "歌", page: 4));
    expect(result.current, 4);
    expect(result.hasMore, isFalse);
    expect(adapter.requests.length, 1);
    dio.close();
  });
}
