import "dart:io";
import "dart:isolate";

import "package:audio_metadata_reader/audio_metadata_reader.dart" as amr;

import "models/track.dart";

/// 原始元数据（读出即止；指纹由扫描器统一计算）
class RawAudioMeta {
  final String? title;
  final String? artist;
  final int? durationMs;

  const RawAudioMeta({this.title, this.artist, this.durationMs});
}

/// 元数据读取抽象：默认走 audio_metadata_reader，测试注入 fake 避开真文件解析
abstract class AudioMetadataSource {
  RawAudioMeta read(File file);
}

class DefaultAudioMetadataSource implements AudioMetadataSource {
  @override
  RawAudioMeta read(File file) {
    final meta = amr.readMetadata(file, getImage: false);
    return RawAudioMeta(
      title: meta.title,
      artist: meta.artist,
      durationMs: meta.duration?.inMilliseconds,
    );
  }
}

/// 扫描结果：入库形状的本地曲目 + 元数据读取失败的文件路径
class LocalScanResult {
  final List<Track> tracks;
  final List<String> failed;

  const LocalScanResult({required this.tracks, required this.failed});
}

/// 本地内容指纹（§3.4-9）：大小 + 时长 + 归一化标题/歌手
/// 归一化 = 去全部空白 + 小写（中文标题空格有无不稳定；英文极端碰撞由大小/时长兜底）
/// → 重扫同一文件得到同一 id，upsert 语义天然保留 liked/歌词
String localAudioFingerprint({
  required int sizeBytes,
  required int durationSec,
  required String title,
  required String artist,
}) {
  String norm(String s) => s.replaceAll(RegExp(r"\s+"), "").toLowerCase();
  return "local:$sizeBytes:$durationSec:${norm(title)}:${norm(artist)}";
}

/// 本地音频扫描器（C3）
/// 生产路径整体在 Isolate.run 中执行（大库同步读元数据不卡 UI）；
/// 注入 [AudioMetadataSource]（测试）时主 isolate 直跑——闭包不可跨 isolate
class LocalAudioScanner {
  /// 音频扩展名白名单（沿 2.7.0）
  static const audioExtensions = {
    ".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".opus",
  };

  /// 判定目录是否排除：名为 Android 的目录（系统私有，不可访问且巨大）、
  /// Download/啵啵音乐（App 下载目录，§3.4-8 防与在线下载条目重复）
  static bool isExcludedDir(Directory dir) {
    final normalized = dir.path.replaceAll("\\", "/");
    if (normalized.split("/").contains("Android")) return true;
    if (normalized.contains("/Download/啵啵音乐")) return true;
    return false;
  }

  Future<LocalScanResult> scan({
    required List<Directory> roots,
    AudioMetadataSource? source,
  }) async {
    if (source != null) return _scanSync(roots, source);
    return Isolate.run(() => _scanSync(roots, DefaultAudioMetadataSource()));
  }

  static LocalScanResult _scanSync(
    List<Directory> roots,
    AudioMetadataSource source,
  ) {
    final tracks = <Track>[];
    final failed = <String>[];
    for (final root in roots) {
      _walk(root, source, tracks, failed);
    }
    return LocalScanResult(tracks: tracks, failed: failed);
  }

  /// 递归扫描：无权限目录静默跳过（系统目录如 lost+found 会拒访）
  static void _walk(
    Directory dir,
    AudioMetadataSource source,
    List<Track> tracks,
    List<String> failed,
  ) {
    final List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final entity in entities) {
      if (entity is Directory) {
        if (!isExcludedDir(entity)) _walk(entity, source, tracks, failed);
      } else if (entity is File && _isAudio(entity.path)) {
        _read(entity, source, tracks, failed);
      }
    }
  }

  static bool _isAudio(String path) {
    final lower = path.toLowerCase();
    return audioExtensions.any(lower.endsWith);
  }

  /// 单文件读元数据：标题缺失回退文件名；歌手缺失记「未知歌手」（沿 2.7.0 文案）
  static void _read(
    File file,
    AudioMetadataSource source,
    List<Track> tracks,
    List<String> failed,
  ) {
    try {
      final meta = source.read(file);
      final fileTitle = file.path
          .replaceAll("\\", "/")
          .split("/")
          .last
          .replaceFirst(RegExp(r"\.[^.]+$"), "");
      final title = (meta.title ?? "").trim().isNotEmpty
          ? meta.title!.trim()
          : fileTitle;
      final artist = (meta.artist ?? "").trim();
      final durationSec = ((meta.durationMs ?? 0) / 1000).round();
      tracks.add(
        Track(
          id: localAudioFingerprint(
            sizeBytes: file.lengthSync(),
            durationSec: durationSec,
            title: title,
            artist: artist,
          ),
          name: title,
          author: artist.isEmpty ? "未知歌手" : artist,
          duration: durationSec,
          origin: OriginType.local,
          localPath: file.path,
        ),
      );
    } catch (_) {
      failed.add(file.path);
    }
  }
}

/// 可替换全局：测试注入扫描结果（跳过权限/文件系统/Isolate，同 hotSingersTestOverride 模式）
LocalScanResult? localScanTestOverride;

/// 扫描入口（生产用）：按平台解析根目录后后台扫描
/// Android 全盘 /storage/emulated/0；其余平台（桌面联调）扫用户主目录下 Music，
/// 不依赖插件通道（path_provider 2.1.5 无音乐目录 API，纯环境变量拼接 Isolate 内可用）
Future<LocalScanResult> scanLocalLibrary() async {
  if (localScanTestOverride != null) return localScanTestOverride!;
  final home =
      Platform.environment["USERPROFILE"] ?? Platform.environment["HOME"] ?? ".";
  final roots = <Directory>[
    if (Platform.isAndroid) Directory("/storage/emulated/0") else Directory("$home/Music"),
  ];
  return LocalAudioScanner().scan(roots: roots);
}
