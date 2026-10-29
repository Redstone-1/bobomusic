import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";
import "package:just_audio/just_audio.dart";

// StreamAudioSource/StreamAudioResponse 官方标注 experimental，
// 自定义流式音源是该注解唯一的标准使用路径
// ignore_for_file: experimental_member_use

/// 解析 Content-Range 头（"bytes 0-999/2000"）→ (end, total)；格式不符返回 null
(int, int)? parseContentRange(String? value) {
  if (value == null) return null;
  final match = RegExp(r"^bytes\s+(\d+)-(\d+)/(\d+)$").firstMatch(value.trim());
  if (match == null) return null;
  return (int.parse(match.group(2)!), int.parse(match.group(3)!));
}

/// 已转正缓存音频判定（.m4a = B 站 dash / .mp3 = 酷我）
bool _isCacheAudio(String path) =>
    path.endsWith(".m4a") || path.endsWith(".mp3");

/// 缓存目录内全部产物（含下载中的 .part）
bool _isCacheArtifact(String path) =>
    _isCacheAudio(path) || path.endsWith(".part");

/// 缓存总量治理（§5.3-5）：超 [maxFiles] 对象或 [maxBytes] 总量时按
/// lastAccessed（LRU）删最旧，直到两项均达标。尽力而为：任何异常不外抛
/// （异步执行，目录被并发清理等竞态直接放弃本轮）
Future<void> pruneAudioCache(
  Directory dir, {
  int maxFiles = 500,
  int maxBytes = 2 * 1024 * 1024 * 1024,
}) async {
  try {
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && _isCacheAudio(e.path)) files.add(e);
    }
    if (files.length <= maxFiles) {
      var total = 0;
      for (final f in files) {
        total += await f.length();
      }
      if (total <= maxBytes) return;
    }
    final statted = <(File, DateTime, int)>[];
    for (final f in files) {
      final stat = await f.stat();
      statted.add((f, stat.accessed, stat.size));
    }
    statted.sort((a, b) => a.$2.compareTo(b.$2)); // 最久未访问在前
    var count = statted.length;
    var bytes = statted.fold<int>(0, (s, e) => s + e.$3);
    for (final (file, _, size) in statted) {
      if (count <= maxFiles && bytes <= maxBytes) break;
      try {
        await file.delete();
        count--;
        bytes -= size;
      } catch (_) {
        // 单文件删除失败（占用等）继续清理其余
      }
    }
  } catch (_) {
    // 治理失败静默放弃（不影响播放主链路）
  }
}

/// B 站 CDN Range 代理源（§5.3，消灭旧链路 P0 全部）：
/// - 上游 Range 直取：seek 秒级响应，不等顺序缓冲，UI 端无 seek hack
/// - 边下边播边落盘：从 0 开始的顺序流 tee 写 .part，完整后转正缓存
///   （key = origin-id 哈希；seek 中断的流不转正）
/// - 15s 无数据看门狗：类型化 TimeoutException，快速失败不挂死
/// - 主直链异常自动降级 backupUrl（退避一次）
///
/// 性能：流式转发不累积整曲（内存有界于网络缓冲），满足"≤10MB 级"验收
class RangeProxySource extends StreamAudioSource {
  /// 播放直链
  final String url;

  /// 备用直链（dash backupUrl；主链失败降级）
  final String? backupUrl;

  /// 请求头（B 站 CDN 必须带 Referer，缺省 403）
  final Map<String, String>? headers;

  /// 流内容类型（B 站 dash 按 video/mp4，酷我 mp3 为 audio/mpeg）
  final String contentType;

  /// 缓存根目录（main 初始化为应用缓存目录下 bobomusic_audio；测试可指临时目录）
  static late Directory cacheDir;

  /// 最高音质优先使用新缓存命名，避免旧低码率文件覆盖新请求；已下载文件不受影响。
  /// 扩展名随音源，下载模块命中即复制。
  static File cacheFileFor(String key) =>
      File("${cacheDir.path}/${md5.convert(utf8.encode("$key|highest-v1"))}"
          "${key.startsWith("kuwo:") ? ".mp3" : ".m4a"}");

  /// 音频缓存占用（音频缓存 + 下载中的 .part，字节）
  static Future<int> cacheSize() async {
    try {
      if (!await cacheDir.exists()) return 0;
      var total = 0;
      await for (final e in cacheDir.list()) {
        if (e is File && _isCacheArtifact(e.path)) {
          total += await e.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 清空音频缓存（保留目录），返回释放字节数
  static Future<int> clearAudioCache() async {
    var freed = 0;
    try {
      if (!await cacheDir.exists()) return 0;
      await for (final e in cacheDir.list()) {
        if (e is File && _isCacheArtifact(e.path)) {
          try {
            freed += await e.length();
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return freed;
  }

  static final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 10)),
  );
  static int _partialSequence = 0;

  late final File _cacheFile;

  RangeProxySource({
    required String key,
    required this.url,
    this.backupUrl,
    this.headers,
    this.contentType = "video/mp4",
  }) : super(tag: key) {
    _cacheFile = cacheFileFor(key);
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    if (s < 0 || (end != null && end < s)) {
      throw RangeError("音频区间不合法：$s..$end");
    }
    if (await _cacheFile.exists()) {
      final total = await _cacheFile.length();
      if (total > 0) {
        if (s > total) throw RangeError.range(s, 0, total);
        final endEx = end != null && end < total ? end : total;
        // just_audio 的 end 排尾，文件读取与 HTTP Range 转换必须保持同一契约。
        return StreamAudioResponse(
          sourceLength: total,
          contentLength: endEx - s,
          offset: s,
          stream: _cacheFile.openRead(s, endEx).cast<Uint8List>(),
          contentType: contentType,
        );
      }
    }
    if (end == s) {
      return StreamAudioResponse(
        sourceLength: null,
        contentLength: 0,
        offset: s,
        stream: const Stream<Uint8List>.empty(),
        contentType: contentType,
      );
    }
    return _fetch(s, end);
  }

  Future<StreamAudioResponse> _fetch(int start, int? end) async {
    final candidates = [
      url,
      if (backupUrl != null && backupUrl!.isNotEmpty && backupUrl != url)
        backupUrl!,
    ];
    Object? lastError;
    for (var index = 0; index < candidates.length; index++) {
      try {
        final first = await _fetchOne(candidates[index], start, end);
        Stream<Uint8List> stream =
            _resumeStream(first, candidates, index, start, end);
        if (start == 0 && first.sourceLength != null) {
          stream = _teeToCache(stream, first.sourceLength!);
        }
        return StreamAudioResponse(
          sourceLength: first.sourceLength,
          contentLength: first.contentLength,
          offset: start,
          stream: stream,
          contentType: contentType,
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError("音频直链请求失败（主/备均不可用）：$lastError");
  }

  /// 流在响应头之后失败时，从已交付字节处接备用链，避免重播前缀或吞掉截断。
  Stream<Uint8List> _resumeStream(
    StreamAudioResponse first,
    List<String> candidates,
    int firstIndex,
    int start,
    int? end,
  ) async* {
    var delivered = 0;
    var current = first;
    Object? lastError;
    for (var index = firstIndex; index < candidates.length; index++) {
      try {
        if (index != firstIndex) {
          current = await _fetchOne(candidates[index], start + delivered, end);
          if (first.sourceLength != null &&
              current.sourceLength != null &&
              first.sourceLength != current.sourceLength) {
            await current.stream.listen((_) {}).cancel();
            throw StateError("主备音频长度不同，无法续传");
          }
        }
        await for (final chunk in current.stream) {
          delivered += chunk.length;
          yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        }
        final expected = first.contentLength;
        if (expected != null && delivered != expected) {
          throw HttpException("音频流不完整：$delivered/$expected");
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError("音频传输中断（主/备均不可用）：$lastError");
  }

  Future<StreamAudioResponse> _fetchOne(
    String candidate,
    int start,
    int? end,
  ) async {
    final token = CancelToken();
    final resp = await _dio.get<ResponseBody>(
      candidate,
      options: Options(
        responseType: ResponseType.stream,
        // HTTP 尾字节含尾，just_audio 尾位置排尾。
        headers: {
          ...?headers,
          "Range": "bytes=$start-${end == null ? "" : end - 1}"
        },
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 1),
      ),
      cancelToken: token,
    );
    final body = resp.data;
    if (body == null) throw StateError("CDN 响应无数据体");
    final range = resp.headers.value("Content-Range");
    final parsed = parseContentRange(range);
    final length = int.tryParse(resp.headers.value("Content-Length") ?? "");
    final int? total;
    final int responseStart;
    final int? availableEnd;
    if (resp.statusCode == HttpStatus.partialContent) {
      final startText = RegExp(r"^bytes\s+(\d+)-").firstMatch(range ?? "");
      if (parsed == null ||
          startText == null ||
          int.parse(startText.group(1)!) != start) {
        token.cancel("无效 Content-Range");
        throw StateError("CDN 返回了不匹配的音频区间");
      }
      total = parsed.$2;
      responseStart = start;
      availableEnd = parsed.$1 + 1;
    } else {
      // 上游忽略 Range 返回 200 时，按整曲总长计算并丢弃 start 之前的字节。
      total = length;
      responseStart = 0;
      availableEnd = length;
    }
    if (total != null && start > total) {
      token.cancel("音频区间越界");
      throw RangeError.range(start, 0, total);
    }
    var endEx = availableEnd;
    if (end != null && (endEx == null || end < endEx)) endEx = end;
    final count = endEx == null ? null : endEx - start;
    final stream = _slice(
      _withWatchdog(body.stream, token),
      start - responseStart,
      count,
    );
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: count,
      offset: start,
      stream: stream,
      contentType: contentType,
    );
  }

  Stream<Uint8List> _slice(
    Stream<Uint8List> source,
    int skip,
    int? remaining,
  ) async* {
    if (remaining == 0) return;
    await for (final chunk in source) {
      if (skip >= chunk.length) {
        skip -= chunk.length;
        continue;
      }
      final from = skip;
      skip = 0;
      final available = chunk.length - from;
      final take =
          remaining != null && remaining < available ? remaining : available;
      yield Uint8List.sublistView(chunk, from, from + take);
      if (remaining != null) {
        remaining -= take;
        if (remaining == 0) return;
      }
    }
  }

  Stream<Uint8List> _withWatchdog(
    Stream<Uint8List> source,
    CancelToken token,
  ) async* {
    try {
      yield* source.timeout(const Duration(seconds: 15), onTimeout: (sink) {
        sink.addError(TimeoutException("音频流 15s 无数据"));
        sink.close();
        token.cancel("音频流看门狗超时");
      });
    } finally {
      if (!token.isCancelled) token.cancel("本次音频区间读取结束");
    }
  }

  /// 缓存写入失败不影响音频；上游断流必须原样传给续传/播放器，不能混为缓存错误。
  Stream<Uint8List> _teeToCache(Stream<Uint8List> source, int total) async* {
    final partial = File(
      "${_cacheFile.path}.${_partialSequence++}.part",
    );
    IOSink? sink;
    Future<void>? sinkDone;
    var healthy = true;
    var complete = false;
    var written = 0;
    void cacheError(Object error) {
      healthy = false;
      print("音频缓存写入失败 [${partial.path}]：$error");
    }

    try {
      try {
        await partial.parent.create(recursive: true);
        sink = partial.openWrite();
        sinkDone = sink.done.then<void>((_) {}, onError: (Object error) {
          cacheError(error);
        });
      } catch (e) {
        cacheError(e);
      }
      await for (final chunk in source) {
        written += chunk.length;
        if (healthy && sink != null) {
          try {
            sink.add(chunk);
          } catch (e) {
            cacheError(e);
          }
        }
        yield chunk;
      }
      complete = true;
    } finally {
      try {
        if (sink != null) {
          try {
            await sink.flush();
          } catch (e) {
            cacheError(e);
          }
          try {
            await sink.close();
          } catch (e) {
            cacheError(e);
          }
          await sinkDone;
        }
        if (complete && healthy && written == total) {
          await partial.rename(_cacheFile.path);
          unawaited(pruneAudioCache(cacheDir));
        }
      } catch (e) {
        cacheError(e);
      } finally {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {
          // 并发清缓存时文件可能已经消失。
        }
      }
    }
  }
}
