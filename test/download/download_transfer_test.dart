import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:bobomusic/features/download/download_transfer.dart";
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  _Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _response(String text,
        {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ResponseBody(
        Stream.fromIterable([Uint8List.fromList(text.codeUnits)]), status,
        headers: {
          "content-length": ["${text.length}"],
          "etag": ['"audio-v1"'],
          ...headers
        });

void main() {
  late Directory temp;
  late File part;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp("bobo_transfer");
    part = File("${temp.path}/audio.part");
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test("暂停保留部分字节，继续发送 Range 和 If-Range 并正确拼接", () async {
    final token = CancelToken();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) => ResponseBody(
              Stream.fromIterable([
                Uint8List.fromList([1, 2, 3]),
                Uint8List.fromList([4, 5, 6])
              ]),
              200,
              headers: {
                "content-length": ["6"],
                "etag": ['"audio-v1"']
              }));
    await expectLater(
        DownloadTransfer(dio).fetch("https://audio.test/a", part,
            cancelToken: token, onProgress: (_) => token.cancel("pause")),
        throwsA(isA<DioException>()));
    expect(await part.readAsBytes(), [1, 2, 3]);
    dio.httpClientAdapter = _Adapter((options) {
      expect(options.headers["Range"], "bytes=3-");
      expect(options.headers["If-Range"], '"audio-v1"');
      return ResponseBody(Stream.value(Uint8List.fromList([4, 5, 6])), 206,
          headers: {
            "content-length": ["3"],
            "content-range": ["bytes 3-5/6"],
            "etag": ['"audio-v1"']
          });
    });
    await DownloadTransfer(dio)
        .fetch("https://audio.test/new-signed-url", part);
    expect(await part.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    dio.close();
  });

  Future<void> saved() async {
    await part.writeAsString("abc");
    await File("${part.path}.json")
        .writeAsString('{"validator":"\\"audio-v1\\"","total":6}');
  }

  test("服务器忽略 Range 时覆盖部分文件，从头下载", () async {
    await saved();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        expect(options.headers["Range"], "bytes=3-");
        return _response("abcdef");
      });
    await DownloadTransfer(dio).fetch("https://audio.test/a", part);
    expect(await part.readAsString(), "abcdef");
    dio.close();
  });

  test("文件标识变化时重新请求完整内容，不能混接", () async {
    await saved();
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        calls++;
        if (calls == 1) {
          return _response("XYZ", status: 206, headers: {
            "content-range": ["bytes 3-5/6"],
            "etag": ['"audio-v2"']
          });
        }
        expect(options.headers.containsKey("Range"), isFalse);
        return _response("UVWXYZ", headers: {
          "etag": ['"audio-v2"']
        });
      });
    await DownloadTransfer(dio).fetch("https://audio.test/a", part);
    expect(await part.readAsString(), "UVWXYZ");
    expect(calls, 2);
    dio.close();
  });

  test("无校验信息不续接，错误范围与截断响应报失败", () async {
    await part.writeAsString("old");
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        expect(options.headers.containsKey("Range"), isFalse);
        return _response("new");
      });
    await DownloadTransfer(dio).fetch("https://audio.test/a", part);
    expect(await part.readAsString(), "new");
    dio.httpClientAdapter =
        _Adapter((_) => _response("abc", status: 206, headers: {
              "content-range": ["bytes 5-7/9"]
            }));
    await expectLater(DownloadTransfer(dio).fetch("https://audio.test/a", part),
        throwsStateError);
    dio.httpClientAdapter = _Adapter((_) => _response("abc", headers: {
          "content-length": ["6"]
        }));
    await expectLater(DownloadTransfer(dio).fetch("https://audio.test/a", part),
        throwsStateError);
    dio.close();
  });

  test("磁盘写入失败也释放响应流，不让后台继续传输", () async {
    var cancelled = false;
    final stream =
        StreamController<Uint8List>(onCancel: () => cancelled = true);
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) => ResponseBody(stream.stream, 200));
    // 元数据文件位置被目录占用，模拟响应头到达后的磁盘错误。
    await Directory("${part.path}.json").create();
    await expectLater(DownloadTransfer(dio).fetch("https://audio.test/a", part),
        throwsA(isA<FileSystemException>()));
    expect(cancelled, isTrue);
    await stream.close();
    dio.close();
  });
}
