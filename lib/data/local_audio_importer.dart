import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:crypto/crypto.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

import "local_audio_scanner.dart";
import "models/track.dart";

/// iOS/桌面文件导入（§2.1）：file_picker 选音频 → 复制到 App 文档目录
/// → 复用扫描器的元数据读取与内容指纹；返回待 upsert 的曲目（不做全量同步，
/// 避免把 Android 全盘扫描的其它本地曲目当成“未再现”删掉）
Future<List<Track>> pickAndImportAudioFiles() async {
  // file_picker 13.x：静态 pickFiles 返回 List<PlatformFile>（多选由平台对话框决定）
  final files = await FilePicker.pickFiles(type: FileType.audio);
  if (files.isEmpty) return const [];
  final paths = <String>[
    for (final file in files)
      if (file.path != null) file.path!,
  ];
  if (paths.isEmpty) return const [];
  final docs = await getApplicationDocumentsDirectory();
  return importAudioFilePaths(
    paths,
    targetDir: Directory(p.join(docs.path, "啵啵音乐导入")),
  );
}

/// 复制到目标目录并扫描（可注入 targetDir/元数据源，测试不碰插件）
Future<List<Track>> importAudioFilePaths(
  List<String> paths, {
  required Directory targetDir,
  AudioMetadataSource? source,
}) async {
  await targetDir.create(recursive: true);
  final copied = <File>[];
  for (final path in paths) {
    try {
      final src = File(path);
      if (!await src.exists()) continue;
      var dest = File(p.join(targetDir.path, p.basename(path)));
      if (p.equals(src.path, dest.path)) {
        copied.add(dest);
        continue;
      }
      // 同名不同内容另存，重复导入相同文件则复用，避免覆盖已经入库的另一首歌。
      var suffix = 1;
      while (await dest.exists()) {
        if (await src.length() == await dest.length() &&
            await md5.bind(src.openRead()).first ==
                await md5.bind(dest.openRead()).first) {
          break;
        }
        dest = File(p.join(targetDir.path,
            "${p.basenameWithoutExtension(path)} (${suffix++})${p.extension(path)}"));
      }
      if (!await dest.exists()) await src.copy(dest.path);
      copied.add(dest);
    } catch (e) {
      print("导入文件失败 [$path]：$e");
    }
  }
  final result = await LocalAudioScanner().scanFiles(copied, source: source);
  return result.tracks;
}
