import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";

import "../../core/permissions/download_permission.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../data/repositories/track_repository.dart";
import "../player/range_proxy_source.dart";
import "download_transfer.dart";

enum DownloadStatus { done, already, failed }

class DownloadResult {
  final DownloadStatus status;
  final String message;
  final String? path;
  final bool interrupted;
  const DownloadResult(this.status, this.message,
      {this.path, this.interrupted = false});
  bool get ok => status != DownloadStatus.failed;
}

/// 临时目录与取流替身只用于测试，不碰真实音源和平台通道。
class DownloadDeps {
  final Future<Directory?> Function() resolveDir;
  final Future<void> Function(Track track, File target) fetch;
  final Future<void> Function(File file)? exportFile;
  const DownloadDeps(
      {required this.resolveDir, required this.fetch, this.exportFile});
}

DownloadDeps? downloadDepsTestOverride;
DownloadService downloadService = DownloadService();

/// 先写临时文件，再转正并登记同一曲目身份；暂停保留部分文件，取消则清理。
class DownloadService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
  ));

  Future<DownloadResult> download(
    Track track, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    File? target;
    var createdTarget = false;
    var registered = false;
    try {
      checkDownloadCancellation(cancelToken);
      await TrackRepository().upsert(track);
      final localPath =
          (await TrackRepository().getById(track.id))?.localPath ??
              track.localPath;
      checkDownloadCancellation(cancelToken);
      if (localPath != null &&
          localPath.isNotEmpty &&
          await File(localPath).exists()) {
        await TrackRepository().markDownloaded(track.id, localPath);
        onProgress?.call(1);
        return DownloadResult(DownloadStatus.already, "已下载，可直接离线播放",
            path: localPath);
      }
      final override = downloadDepsTestOverride;
      if (override == null && !await requestDownloadPermission()) {
        return const DownloadResult(DownloadStatus.failed, "未获得存储权限，无法写入下载目录");
      }
      final dir = override != null
          ? await override.resolveDir()
          : await _resolvePlatformDir();
      if (dir == null) throw StateError("无法访问下载目录");
      await dir.create(recursive: true);
      target = File(p.join(dir.path, downloadFileName(track)));
      final partial = File("${target.path}.part");
      checkDownloadCancellation(cancelToken);
      if (await target.exists() && await target.length() > 0) {
        await TrackRepository().markDownloaded(track.id, target.path);
        onProgress?.call(1);
        return DownloadResult(DownloadStatus.already, "已下载：${target.path}",
            path: target.path);
      }
      final cache = RangeProxySource.cacheFileFor(track.id);
      if (await cache.exists() && await cache.length() > 0) {
        await cache.copy(partial.path);
      } else if (override != null) {
        await override.fetch(track, partial);
      } else {
        await _fetch(track, partial, onProgress, cancelToken);
      }
      checkDownloadCancellation(cancelToken);
      if (!await partial.exists() || await partial.length() == 0) {
        throw StateError("下载结果为空，请重试");
      }
      await partial.rename(target.path);
      createdTarget = true;
      checkDownloadCancellation(cancelToken);
      await TrackRepository().markDownloaded(track.id, target.path);
      registered = true;
      checkDownloadCancellation(cancelToken);
      await _deleteFile(File("${partial.path}.json"));
      onProgress?.call(1);
      if (override?.exportFile != null || Platform.isIOS) {
        try {
          if (override?.exportFile != null) {
            await override!.exportFile!(target);
          } else {
            await SharePlus.instance
                .share(ShareParams(files: [XFile(target.path)]));
          }
        } catch (e) {
          print("导出文件失败：$e");
        }
      }
      return DownloadResult(DownloadStatus.done, "已下载：${target.path}",
          path: target.path);
    } catch (e) {
      final interrupted = cancelToken?.isCancelled == true;
      final paused = interrupted && cancelToken?.cancelError?.error == "pause";
      if (registered) await TrackRepository().clearDownloaded(track.id);
      if (createdTarget && target != null) await _deleteFile(target);
      if (!paused && target != null) await _discardTargetPartial(target);
      return DownloadResult(DownloadStatus.failed,
          interrupted ? (paused ? "下载已暂停" : "下载已取消") : "下载失败：$e",
          interrupted: interrupted);
    }
  }

  Future<void> discardPartial(Track track) async {
    final override = downloadDepsTestOverride;
    final dir = override != null
        ? await override.resolveDir()
        : await _resolvePlatformDir();
    if (dir != null) {
      await _discardTargetPartial(
          File(p.join(dir.path, downloadFileName(track))));
    }
  }

  Future<void> _discardTargetPartial(File target) async {
    await _deleteFile(File("${target.path}.part"));
    await _deleteFile(File("${target.path}.part.json"));
  }

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      print("清理下载临时文件失败：$e");
    }
  }

  Future<void> _fetch(Track track, File target,
      void Function(double)? onProgress, CancelToken? cancelToken) async {
    if (track.origin == OriginType.local) {
      final path = track.localPath;
      if (path == null || !await File(path).exists()) {
        throw StateError("本地文件不存在");
      }
      await File(path).copy(target.path);
      return;
    }
    final musicUrl = switch (track.origin) {
      OriginType.kuwo => await kuwoApi.getMusicUrl(track.id),
      OriginType.netease => await neteaseApi.getMusicUrl(track.id),
      OriginType.qq => await qqApi.getMusicUrl(track.id),
      OriginType.qianqian => await qianqianApi.getMusicUrl(track.id),
      _ => await biliApi.getMusicUrl(track.id),
    };
    checkDownloadCancellation(cancelToken);
    await DownloadTransfer(_dio).fetch(musicUrl.url, target,
        headers: musicUrl.headers,
        cancelToken: cancelToken,
        onProgress: onProgress);
  }

  Future<Directory?> _resolvePlatformDir() async {
    if (Platform.isAndroid) {
      return Directory("/storage/emulated/0/Download/啵啵音乐");
    }
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, "啵啵音乐"));
    }
    final base = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, "啵啵音乐"));
  }
}

/// 身份摘要隔离同名歌曲；旧下载仍优先通过数据库登记的 localPath 找回。
String downloadFileName(Track track) {
  var safe = "${track.name} - ${track.author}"
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), "_")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
  if (safe.isEmpty) safe = "音乐";
  if (safe.length > 67) safe = safe.substring(0, 67);
  safe =
      "$safe [${md5.convert(utf8.encode(track.id)).toString().substring(0, 10)}]";
  final ext = track.localPath == null ? "" : p.extension(track.localPath!);
  return "$safe${ext.isNotEmpty ? ext : track.origin == OriginType.bili ? ".m4a" : ".mp3"}";
}
