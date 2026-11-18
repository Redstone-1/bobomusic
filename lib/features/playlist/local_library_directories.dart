import "package:file_picker/file_picker.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:path/path.dart" as p;

import "../../core/prefs/app_prefs.dart";

/// 目录 URI 转本地路径：桌面端 pickDirectory 返回 file:// 目录 URI，恒带尾分隔符，
/// 剥掉以保持与旧 getDirectoryPath 一致的落库形态；盘根（如 D:\）不剥，
/// 剥了会退化成盘符相对路径。目录管理入口仅桌面（扫描走 Dart IO 路径，
/// Android 的 content:// 树 URI 不适用本流程）。
String? _directoryUriToPath(Uri? uri) {
  if (uri == null) return null;
  final path = uri.toFilePath();
  final isDriveRoot = path.length == 3 && path.endsWith(":\\");
  return (path.length > 1 && !isDriveRoot)
      ? path.substring(0, path.length - 1)
      : path;
}

final musicDirectoryPickerProvider = Provider<Future<String?> Function()>(
    (ref) => () async => _directoryUriToPath(
        await FilePicker.pickDirectory(dialogTitle: "选择音乐文件夹")));

/// 目录偏好只决定扫描范围；移除目录配置不会删除歌曲或原文件。
class LocalLibraryDirectories extends Notifier<List<String>> {
  static const _key = "windows_music_directories";
  @override
  List<String> build() => appPrefs.getStringList(_key) ?? const [];

  Future<void> add(String path) async {
    final normalized = p.normalize(p.absolute(path));
    if (state.any((item) => p.equals(item, normalized))) return;
    final updated = [...state, normalized];
    if (!await appPrefs.setStringList(_key, updated)) {
      throw StateError("扫描目录保存失败");
    }
    if (ref.mounted) state = updated;
  }

  Future<void> remove(String path) async {
    final updated = state.where((item) => !p.equals(item, path)).toList();
    if (!await appPrefs.setStringList(_key, updated)) {
      throw StateError("扫描目录保存失败");
    }
    if (ref.mounted) state = updated;
  }
}

final localLibraryDirectoriesProvider =
    NotifierProvider<LocalLibraryDirectories, List<String>>(
        LocalLibraryDirectories.new);
