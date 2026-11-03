import "dart:async";
import "dart:convert";
import "dart:ui";

import "package:screen_retriever/screen_retriever.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:window_manager/window_manager.dart";

const windowsMinimumSize = Size(800, 600);
const windowsInitialSize = Size(1440, 900);
const _preferenceKey = "windows_window_state";

/// 只在可用显示区域中恢复窗口；旧显示器离线时回到主屏幕，标题栏始终可见。
Rect restoreWindowsBounds(Rect? saved, List<Rect> workAreas) {
  final areas = workAreas.where((r) => r.width > 0 && r.height > 0).toList();
  final primary =
      areas.isEmpty ? const Rect.fromLTWH(0, 0, 1440, 900) : areas.first;
  final valid = saved != null &&
      saved.left.isFinite &&
      saved.top.isFinite &&
      saved.width.isFinite &&
      saved.height.isFinite &&
      saved.width > 0 &&
      saved.height > 0;
  var area = primary;
  if (valid) {
    for (final candidate in areas) {
      if (candidate.contains(saved.topLeft + const Offset(40, 16))) {
        area = candidate;
        break;
      }
    }
  }
  final width = (valid ? saved.width : windowsInitialSize.width)
      .clamp(windowsMinimumSize.width.clamp(0, area.width), area.width)
      .toDouble();
  final height = (valid ? saved.height : windowsInitialSize.height)
      .clamp(windowsMinimumSize.height.clamp(0, area.height), area.height)
      .toDouble();
  final usePosition =
      valid && area.contains(saved.topLeft + const Offset(40, 16));
  final left = usePosition ? saved.left : area.left + (area.width - width) / 2;
  final top = usePosition ? saved.top : area.top + (area.height - height) / 2;
  return Rect.fromLTWH(left.clamp(area.left, area.right - width).toDouble(),
      top.clamp(area.top, area.bottom - height).toDouble(), width, height);
}

class WindowsWindowController with WindowListener {
  WindowsWindowController(this._prefs);

  final SharedPreferences _prefs;
  Timer? _saveTimer;
  Rect? _normalBounds;
  bool _closing = false;
  Future<void> Function()? beforeClose;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    Map<String, dynamic> saved = {};
    try {
      final value = jsonDecode(_prefs.getString(_preferenceKey) ?? "{}");
      if (value is Map<String, dynamic>) saved = value;
    } catch (error) {
      print("窗口偏好无效，恢复默认窗口：$error");
    }
    Rect? oldBounds;
    if (["x", "y", "width", "height"].every((key) => saved[key] is num)) {
      oldBounds = Rect.fromLTWH(
          (saved["x"] as num).toDouble(),
          (saved["y"] as num).toDouble(),
          (saved["width"] as num).toDouble(),
          (saved["height"] as num).toDouble());
    }
    final primary = await screenRetriever.getPrimaryDisplay();
    final displays = await screenRetriever.getAllDisplays();
    final ordered = [primary, ...displays.where((d) => d.id != primary.id)];
    final areas = ordered
        .map((d) =>
            (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size))
        .toList();
    _normalBounds = restoreWindowsBounds(oldBounds, areas);
    await windowManager.waitUntilReadyToShow(const WindowOptions(
      title: "啵啵音乐",
      minimumSize: windowsMinimumSize,
      titleBarStyle: TitleBarStyle.normal,
    ));
    await windowManager.setBounds(_normalBounds);
    if (saved["maximized"] == true) await windowManager.maximize();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (error) {
      dispose();
      await windowManager.setPreventClose(false);
      rethrow;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer =
        Timer(const Duration(milliseconds: 300), () => unawaited(save()));
  }

  Future<void> save() async {
    try {
      if (await windowManager.isMinimized()) return;
      final maximized = await windowManager.isMaximized();
      if (!maximized) _normalBounds = await windowManager.getBounds();
      final bounds = _normalBounds;
      if (bounds == null) return;
      await _prefs.setString(
          _preferenceKey,
          jsonEncode({
            "x": bounds.left,
            "y": bounds.top,
            "width": bounds.width,
            "height": bounds.height,
            "maximized": maximized,
          }));
    } catch (error) {
      print("保存窗口状态失败：$error");
    }
  }

  @override
  void onWindowMoved() => _scheduleSave();
  @override
  void onWindowResized() => _scheduleSave();
  @override
  void onWindowMaximize() => _scheduleSave();
  @override
  void onWindowUnmaximize() => _scheduleSave();
  @override
  void onWindowClose() => unawaited(close());

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      _saveTimer?.cancel();
      await save();
      await beforeClose?.call();
      await windowManager.destroy();
    } catch (error) {
      _closing = false;
      print("关闭窗口失败：$error");
    }
  }

  void dispose() {
    _saveTimer?.cancel();
    windowManager.removeListener(this);
  }
}

WindowsWindowController? windowsWindowController;
