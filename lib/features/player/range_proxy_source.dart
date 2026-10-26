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
  final match =
      RegExp(r"^bytes\s+(\d+)-(\d+)/(\d+)$").firstMatch(value.trim());
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

  /// 缓存文件（key=origin-id 的 md5 文件名；扩展名随音源，下载模块命中即复制）
  static File cacheFileFor(String key) => File(
      "${cacheDir.path}/${md5.convert(utf8.encode(key))}"
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

  static final Dio _dio = Dio();

  late final File _cacheFile;
  late final File _partFile;

  RangeProxySource({
    required String key,
    required this.url,
    this.backupUrl,
    this.headers,
    this.contentType = "video/mp4",
  }) : super(tag: key) {
    // origin-id 可能含路径非法字符（冒号等），md5 短哈希作缓存文件名
    final name = md5.convert(utf8.encode(key)).toString();
    _cacheFile = cacheFileFor(key);
    _partFile = File("${cacheDir.path}/$name.part");
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    // 缓存命中：本地文件直读（老用户/重听秒开）
    if (await _cacheFile.exists()) {
      final total = await _cacheFile.length();
      final last = end != null && end < total - 1 ? end : total - 1;
      return StreamAudioResponse(
        sourceLength: total,
        contentLength: last - s + 1,
        offset: s,
        stream: _cacheFile.openRead(s, last + 1).cast<Uint8List>(),
        // B 站 dash 按 video/mp4 声明（实际 m4a），demux 依赖此声明
        contentType: contentType,
      );
    }
    return _fetch(s, end);
  }

  Future<StreamAudioResponse> _fetch(int start, int? end) async {
    Object? lastError;
    final candidates = [
      url,
      if (backupUrl != null && backupUrl!.isNotEmpty) backupUrl!,
    ];
    for (final candidate in candidates) {
      try {
        return await _fetchOne(candidate, start, end);
      } on TimeoutException {
        // 看门狗超时视为链路问题，继续降级
        lastError ??= TimeoutException("音频流 15s 无数据（看门狗）");
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError("音频直链请求失败（主/备均不可用）：$lastError");
  }

  Future<StreamAudioResponse> _fetchOne(String candidate, int start, int? end) async {
    final cancelToken = CancelToken();
    final range = "bytes=$start-${end ?? ""}";
    final resp = await _dio.get<ResponseBody>(
      candidate,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...?headers, "Range": range},
        // CDN 直链响应慢是常态，连接超时收紧；读超时由看门狗负责
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 1),
      ),
      cancelToken: cancelToken,
    );
    final body = resp.data;
    if (body == null) throw StateError("CDN 响应无数据体");
    final (endIdx, total) = _resolveExtent(resp, start);
    Stream<Uint8List> stream = body.stream;
    // 看门狗：15s 无数据快速失败（下游订阅取消时 Dio 一并中止）
    stream = _withWatchdog(stream, cancelToken);
    // 顺序流（自 0）tee 落盘；seek 触发的中段流不落盘
    if (start == 0) {
      await _partFile.parent.create(recursive: true);
      if (await _partFile.exists()) await _partFile.delete();
      stream = _teeToCache(stream, total);
    }
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: endIdx - start + 1,
      offset: start,
      stream: stream,
      contentType: contentType,
    );
  }

  /// 从响应头确定 (end, total)：206 用 Content-Range；兜底 Content-Length
  (int, int) _resolveExtent(Response<ResponseBody> resp, int start) {
    final parsed = parseContentRange(resp.headers.value("Content-Range"));
    if (parsed != null) return parsed;
    final cl = resp.headers.value("Content-Length");
    final length = cl != null ? int.tryParse(cl) ?? 0 : 0;
    return (start + length - 1, start + length);
  }

  Stream<Uint8List> _withWatchdog(
    Stream<Uint8List> src,
    CancelToken token,
  ) async* {
    var expired = false;
    Timer? watchdog;
    void reset() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 15), () {
        expired = true;
        token.cancel("音频流看门狗：15s 无数据");
      });
    }

    reset();
    try {
      await for (final chunk in src) {
        if (expired) break;
        reset();
        yield chunk;
      }
    } finally {
      watchdog?.cancel();
    }
    if (expired) {
      throw TimeoutException("音频流 15s 无数据（看门狗）");
    }
  }

  /// 顺序流旁路落盘：完整（== total）后 .part 转正为缓存文件并触发 LRU 清理
  Stream<Uint8List> _teeToCache(Stream<Uint8List> src, int total) async* {
    IOSink? sink;
    try {
      sink = _partFile.openWrite();
      var written = 0;
      await for (final chunk in src) {
        yield chunk;
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (written == total) {
        await _partFile.rename(_cacheFile.path);
        // 治理异步执行，不阻塞播放
        unawaited(pruneAudioCache(cacheDir));
      } else {
        await _partFile.delete();
      }
    } catch (e) {
      // 落盘失败不影响播放（网络流已由下游消费），但必须可见，防吞内部错误
      print("音频缓存落盘失败 [${_cacheFile.path}]: $e");
      await sink?.close();
      if (await _partFile.exists()) {
        try {
          await _partFile.delete();
        } catch (_) {}
      }
    }
  }
}
