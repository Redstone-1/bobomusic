import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";

void checkDownloadCancellation(CancelToken? token) {
  if (token?.isCancelled == true) throw token!.cancelError!;
}

/// 仅带强 ETag 或 Last-Modified 的部分文件可续传；签名直链变化不代表文件相同。
class DownloadTransfer {
  final Dio dio;
  DownloadTransfer(this.dio);

  Future<void> fetch(
    String url,
    File partial, {
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    void Function(double)? onProgress,
  }) async {
    checkDownloadCancellation(cancelToken);
    final metadata = File("${partial.path}.json");
    var offset = 0;
    String? validator;
    int? knownTotal;
    try {
      final saved = jsonDecode(await metadata.readAsString()) as Map;
      validator = saved["validator"] as String?;
      knownTotal = saved["total"] as int?;
      if (validator != null && validator.isNotEmpty && await partial.exists()) {
        offset = await partial.length();
        if (knownTotal == null || offset >= knownTotal) offset = 0;
      }
    } catch (_) {
      // 无校验信息的旧临时文件不能安全拼接，继续操作会从头取流。
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      checkDownloadCancellation(cancelToken);
      final requestHeaders = <String, dynamic>{
        for (final entry in (headers ?? <String, dynamic>{}).entries)
          if (!["range", "if-range", "accept-encoding"]
              .contains(entry.key.toLowerCase()))
            entry.key: entry.value,
        "Accept-Encoding": "identity",
        if (offset > 0) "Range": "bytes=$offset-",
        if (offset > 0) "If-Range": validator,
      };
      // Dio 的响应流取消不会自动关闭所有适配器，用独立请求令牌确保异常也中断底层连接。
      final transferToken = CancelToken();
      if (cancelToken != null) {
        cancelToken.whenCancel
            .then((error) => transferToken.cancel(error.error));
      }
      try {
        final response = await dio.get<ResponseBody>(
          url,
          options: Options(
              headers: requestHeaders, responseType: ResponseType.stream),
          cancelToken: transferToken,
        );
        final body = response.data!;
        var subscribed = false;
        try {
          final etag = response.headers.value("etag");
          final currentValidator = etag != null && !etag.startsWith("W/")
              ? etag
              : response.headers.value("last-modified");
          final range = RegExp(r"^bytes (\d+)-(\d+)/(\d+)$")
              .firstMatch(response.headers.value("content-range") ?? "");
          final length =
              int.tryParse(response.headers.value("content-length") ?? "");
          var total = length;
          if (response.statusCode == 206) {
            final start = range == null ? -1 : int.parse(range[1]!);
            final end = range == null ? -1 : int.parse(range[2]!);
            total = range == null ? null : int.parse(range[3]!);
            if (range == null ||
                start != offset ||
                end < start ||
                end >= total! ||
                (length != null && length != end - start + 1)) {
              throw StateError("服务器续传范围无效，请重试");
            }
            if (offset > 0 &&
                (currentValidator != validator || total != knownTotal)) {
              offset = 0;
              continue;
            }
          } else if (response.statusCode == 200) {
            // 忽略 Range 的服务器返回完整文件，覆盖部分文件，绝不追加重复字节。
            offset = 0;
          } else {
            throw StateError("服务器未返回音频文件：${response.statusCode}");
          }
          await metadata.writeAsString(
              jsonEncode({"validator": currentValidator, "total": total}),
              flush: true);
          final output = await partial.open(
              mode: offset > 0 ? FileMode.append : FileMode.write);
          var received = offset;
          try {
            subscribed = true;
            await for (final chunk in body.stream) {
              checkDownloadCancellation(cancelToken);
              await output.writeFrom(chunk);
              received += chunk.length;
              if (total != null && total > 0) {
                onProgress?.call(received / total);
              }
            }
            checkDownloadCancellation(cancelToken);
            if (received == 0 || (total != null && received != total)) {
              throw StateError("下载未完成，请重试");
            }
            await output.flush();
          } finally {
            await output.close();
          }
          return;
        } finally {
          if (!subscribed) await body.stream.listen(null).cancel();
        }
      } finally {
        transferToken.cancel("transfer-finished");
        await transferToken.whenCancel;
      }
    }
    throw StateError("文件校验已变化，请重新下载");
  }
}
