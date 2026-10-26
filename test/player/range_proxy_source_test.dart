import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:bobomusic/features/player/range_proxy_source.dart";
import "package:crypto/crypto.dart";
import "package:flutter_test/flutter_test.dart";

/// RangeProxySource 本地集成测试：真实 dio 请求打本地 HttpServer，
/// 覆盖 206/200/降级/缓存命中（不依赖真网络与播放器平台通道）
void main() {
  late HttpServer server;
  late Directory cacheDir;

  // 8KB 假音频内容（确定性字节）
  final content = Uint8List.fromList(
    List.generate(8192, (i) => i % 251),
  );
  // 服务器行为开关
  var mode = "range206";
  var refererSeen = false;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp("bobo_range_test");
    RangeProxySource.cacheDir = cacheDir;
    refererSeen = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      refererSeen = request.headers.value("Referer") != null;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      switch (mode) {
        case "reject403":
          request.response.statusCode = 403;
          await request.response.close();
          return;
        case "plain200": // 不支持 Range：整曲 200
          request.response.statusCode = 200;
          request.response.headers.contentLength = content.length;
          request.response.add(content);
          await request.response.close();
          return;
        default: // range206：标准 Range 支持
          final match = RegExp(r"bytes=(\d+)-(\d*)").firstMatch(range ?? "");
          final start = match != null ? int.parse(match.group(1)!) : 0;
          final end = match != null && match.group(2)!.isNotEmpty
              ? int.parse(match.group(2)!)
              : content.length - 1;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            "bytes $start-$end/${content.length}",
          );
          final chunk = content.sublist(start, end + 1);
          request.response.headers.contentLength = chunk.length;
          request.response.add(chunk);
          await request.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    try {
      cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  RangeProxySource buildSource({String? backup}) => RangeProxySource(
        key: "test_track",
        url: "http://127.0.0.1:${server.port}/audio.m4s",
        backupUrl: backup == null ? null : "http://127.0.0.1:${server.port}/$backup",
        headers: const {"Referer": "https://www.bilibili.com/"},
      );

  Future<Uint8List> drain(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  test("206 Range 请求：全量读回内容一致，元数据正确", () async {
    mode = "range206";
    final source = buildSource();
    final resp = await source.request(0, null);
    expect(resp.sourceLength, content.length);
    expect(resp.offset, 0);
    expect(resp.contentType, "video/mp4");
    expect(refererSeen, isTrue, reason: "必须带 Referer");
    final data = await drain(resp.stream);
    expect(data.length, content.length);
    expect(data, content);
  });

  test("contentType 透传：酷我流按 audio/mpeg 声明", () async {
    mode = "range206";
    final source = RangeProxySource(
      key: "kuwo:123",
      url: "http://127.0.0.1:${server.port}/audio.mp3",
      headers: const {"Referer": "https://www.kuwo.cn/"},
      contentType: "audio/mpeg",
    );
    final resp = await source.request(0, null);
    expect(resp.contentType, "audio/mpeg");
    expect(await drain(resp.stream), content);
  });

  test("缓存文件扩展名随音源：kuwo: 前缀 .mp3，其余 .m4a", () {
    expect(
      RangeProxySource.cacheFileFor("kuwo:123").path.endsWith(".mp3"),
      isTrue,
    );
    expect(
      RangeProxySource.cacheFileFor("bili:1_BVx_2").path.endsWith(".m4a"),
      isTrue,
    );
  });

  test("中段 Range（模拟 seek）：字节区间正确", () async {
    mode = "range206";
    final source = buildSource();
    final resp = await source.request(1000, 1999);
    expect(resp.offset, 1000);
    expect(resp.contentLength, 1000);
    final data = await drain(resp.stream);
    expect(data, content.sublist(1000, 2000));
  });

  test("整曲顺序播完：落盘转正缓存，二次请求文件直读", () async {
    mode = "range206";
    final port = server.port;
    final source = buildSource();
    final first = await source.request(0, null);
    await drain(first.stream); // 完整消费 → 转正
    await Future<void>.delayed(Duration.zero);
    final cached = File(
      "${cacheDir.path}/${md5.convert(utf8.encode("test_track"))}.m4a",
    );
    expect(await cached.exists(), isTrue, reason: "顺序流完整后应转正缓存");
    // 命中缓存：不再走网络（服务器关掉也能读）
    await server.close(force: true);
    final second = await RangeProxySource(
      key: "test_track",
      url: "http://127.0.0.1:$port/audio.m4s",
      headers: const {"Referer": "https://www.bilibili.com/"},
    ).request(0, null);
    final data = await drain(second.stream);
    expect(data, content);
  });

  test("主链 403 → 降级备用直链成功", () async {
    // 主链 403、备链 200：按 path 区分（重开服务前先记端口）
    final port = server.port;
    await server.close(force: true);
    final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server2.listen((request) async {
      if (request.uri.path == "/main.m4s") {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      request.response.statusCode = 200;
      request.response.headers.contentLength = content.length;
      request.response.add(content);
      await request.response.close();
    });
    final source = RangeProxySource(
      key: "failover",
      url: "http://127.0.0.1:$port/main.m4s",
      backupUrl: "http://127.0.0.1:$port/ok.m4s",
      headers: const {"Referer": "https://www.bilibili.com/"},
    );
    final resp = await source.request(0, null);
    final data = await drain(resp.stream);
    expect(data, content);
  });

  test("200 无 Range 支持兜底：以 Content-Length 推算总长", () async {
    mode = "plain200";
    final source = buildSource();
    final resp = await source.request(0, null);
    expect(resp.sourceLength, content.length);
    final data = await drain(resp.stream);
    expect(data, content);
  });

  test("酷我 mp3：缓存文件名 .mp3，contentType 按 audio/mpeg 声明", () async {
    mode = "range206";
    final source = RangeProxySource(
      key: "kuwo:123",
      url: "http://127.0.0.1:${server.port}/audio.mp3",
      contentType: "audio/mpeg",
    );
    final resp = await source.request(0, null);
    expect(resp.contentType, "audio/mpeg");
    await drain(resp.stream);
    await Future<void>.delayed(Duration.zero);

    final cached = RangeProxySource.cacheFileFor("kuwo:123");
    expect(cached.path.endsWith(".mp3"), isTrue);
    expect(await cached.exists(), isTrue);
  });

  test("parseContentRange 解析与容错", () {
    expect(parseContentRange("bytes 0-999/2000"), (999, 2000));
    expect(parseContentRange("bytes 100-199/2000"), (199, 2000));
    expect(parseContentRange(null), isNull);
    expect(parseContentRange("garbage"), isNull);
    expect(parseContentRange("bytes */2000"), isNull);
  });
}
