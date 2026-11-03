import "package:file_picker/file_picker.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:path/path.dart" as p;

import "../../core/prefs/app_prefs.dart";

final musicDirectoryPickerProvider = Provider<Future<String?> Function()>(
    (ref) => () => FilePicker.getDirectoryPath(dialogTitle: "选择音乐文件夹"));

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
