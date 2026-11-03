import "package:flutter/widgets.dart";

/// 中央 Navigator 内复用手机内容视图，统一去除重复背景、迷你条和返回入口。
class DesktopContent extends InheritedWidget {
  const DesktopContent({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopContent>() != null;
  @override
  bool updateShouldNotify(DesktopContent oldWidget) => false;
}
