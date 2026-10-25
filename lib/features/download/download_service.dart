import "dart:io";

import "package:dio/dio.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";

import "../../core/permissions/download_permission.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../data/repositories/track_repository.dart";
import "../player/range_proxy_source.dart";

enum DownloadStatus { done, already, failed }

class DownloadResult {
  final DownloadStatus status;
  final String message;
  final String? path;

  const DownloadResult(this.status, this.message, {this.path});

  bool get ok => status != DownloadStatus.failed;
}

/// 下载依赖注入（测试用：临时目录 + 假取流，不碰网络/平台通道）
class DownloadDeps {
  final Future<Directory?> Function() resolveDir;
  final Future<void> Function(Track track, File target) fetch;
  final Future<void> Function(File file)? exportFile;

  const DownloadDeps({
    required this.resolveDir,
    required this.fetch,
    this.exportFile,
  });
}

DownloadDeps? downloadDepsTestOverride;

/// 全局下载服务（测试可替换）
DownloadService downloadService = DownloadService();

/// 下载模块（§3.4-8）：同一曲目身份登记 localPath，离线可播
/// - 命中播放缓存 → 直接复制（不重复消耗流量）
/// - 未命中 → 按音源取直链下载（B 站/酷我；本地曲直接复制）
/// - 成功后写 tracks.local_path + downloaded_at；列表/播放读取同一 Track 身份
class DownloadService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  Future<DownloadResult> download(Track track) async {
    // 已是本地可播文件（本地扫描/上次下载）
    final localPath = track.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      try {
        if (await File(localPath).exists()) {
          await TrackRepository().markDownloaded(track.id, localPath);
          return const DownloadResult(
            DownloadStatus.already,
            "已下载，可直接离线播放",
          );
        }
      } catch (_) {
        // 路径不可读时继续走下载
      }
    }

    final override = downloadDepsTestOverride;
    if (override == null && !await requestDownloadPermission()) {
      return const DownloadResult(
        DownloadStatus.failed,
        "未获得存储权限，无法写入下载目录",
      );
    }
    final dir = override != null
        ? await override.resolveDir()
        : await _resolvePlatformDir();
    if (dir == null) {
      return const DownloadResult(DownloadStatus.failed, "无法访问下载目录");
    }
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, downloadFileName(track)));

    try {
      // 目标已存在且非空：视为已下载（避免重复占空间）
      if (await target.exists() && await target.length() > 0) {
        await TrackRepository().markDownloaded(track.id, target.path);
        return DownloadResult(
          DownloadStatus.already,
          "已下载：${target.path}",
          path: target.path,
        );
      }

      // 播放缓存命中 → 复制；key/md5 与 RangeProxySource 完全一致
      final cache = RangeProxySource.cacheFileFor(track.id);
      if (await cache.exists() && await cache.length() > 0) {
        await cache.copy(target.path);
      } else if (override != null) {
        await override.fetch(track, target);
      } else {
        await _fetch(track, target);
      }

      if (!await target.exists() || await target.length() == 0) {
        return const DownloadResult(DownloadStatus.failed, "下载结果为空，请重试");
      }
      await TrackRepository().markDownloaded(track.id, target.path);

      // iOS 不能写公共下载目录：保存到文档目录后调起分享面板导出
      if (override?.exportFile != null) {
        await override!.exportFile!(target);
      } else if (Platform.isIOS) {
        await _export(target);
      }
      return DownloadResult(
        DownloadStatus.done,
        "已下载：${target.path}",
        path: target.path,
      );
    } catch (e) {
      // 失败不留半成品
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      return DownloadResult(DownloadStatus.failed, "下载失败：$e");
    }
  }

  Future<void> _fetch(Track track, File target) async {
    // 本地曲（路径存在但上面未命中，通常为异常）直接复制文件
    if (track.origin == OriginType.local) {
      final src = track.localPath;
      if (src == null || !await File(src).exists()) {
        throw StateError("本地文件不存在");
      }
      await File(src).copy(target.path);
      return;
    }
    final musicUrl = track.origin == OriginType.kuwo
        ? await kuwoApi.getMusicUrl(track.id)
        : await biliApi.getMusicUrl(track.id);
    await _dio.download(
      musicUrl.url,
      target.path,
      options: Options(headers: musicUrl.headers),
    );
  }

  Future<Directory?> _resolvePlatformDir() async {
    if (Platform.isAndroid) {
      // 与旧版一致：公共 Download/啵啵音乐（扫描器已排除，防重复）
      return Directory("/storage/emulated/0/Download/啵啵音乐");
    }
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, "啵啵音乐"));
    }
    final downloads = await getDownloadsDirectory();
    final base = downloads ?? await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, "啵啵音乐"));
  }

  Future<void> _export(File file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)]),
    );
  }
}

/// 文件名清洗（纯函数）：去掉路径非法字符、压缩空白、限制长度
/// 在线曲固定 .m4a（B 站 dash / 酷我 mp3 由下载器写原始字节，扩展名仅作展示）
String downloadFileName(Track track) {
  final raw = "${track.name} - ${track.author}".trim();
  var safe = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), "_")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
  if (safe.isEmpty) safe = track.id;
  if (safe.length > 80) safe = safe.substring(0, 80);
  final localExt = track.localPath == null ? "" : p.extension(track.localPath!);
  return "$safe${localExt.isEmpty ? ".m4a" : localExt}";
}
