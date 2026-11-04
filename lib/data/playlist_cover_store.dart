import "dart:io";
import "dart:math";
import "dart:ui" as ui;

import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

import "repositories/playlist_repository.dart";

/// 设备选图复制到应用持久目录，避免选择器临时授权或缓存失效。
class PlaylistCoverStore {
  PlaylistCoverStore({Future<Directory> Function()? directory})
      : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async => Directory(
      p.join((await getApplicationSupportDirectory()).path, "playlist_covers"));

  Future<String> importFile(File source) async {
    if (await source.length() > 20 * 1024 * 1024) {
      throw const FormatException("图片不能超过 20 MB");
    }
    final bytes = await source.readAsBytes();
    // 实际解码验证，扩展名正确但内容损坏的文件不能保存为封面。
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    final suffix = p.extension(source.path).toLowerCase();
    final name =
        "${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}$suffix";
    final target = File(p.join(directory.path, name));
    await target.writeAsBytes(bytes, flush: true);
    return target.uri.toString();
  }

  Future<void> removeIfUnused(String? cover) async {
    if (cover == null || Uri.tryParse(cover)?.scheme != "file") return;
    try {
      final directory = await _directory();
      final file = File.fromUri(Uri.parse(cover));
      if (!p.isWithin(p.normalize(p.absolute(directory.path)),
          p.normalize(p.absolute(file.path)))) {
        return;
      }
      if (await PlaylistRepository().isCoverReferenced(cover)) return;
      if (await file.exists()) await file.delete();
    } catch (error) {
      // 清理失败不影响已经保存的歌单，也不删除目录外的用户图片。
      print("清理未引用歌单封面失败：$error");
    }
  }
}
