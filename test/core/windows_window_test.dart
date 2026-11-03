import "dart:ui";

import "package:bobomusic/core/window/windows_window.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  const primary = Rect.fromLTWH(0, 0, 1920, 1040);
  test("外接屏离线时窗口回到主屏并完整可见", () {
    final bounds = restoreWindowsBounds(
        const Rect.fromLTWH(2500, 150, 1400, 900), [primary]);
    expect(primary.contains(bounds.topLeft), isTrue);
    expect(bounds.right <= primary.right && bounds.bottom <= primary.bottom,
        isTrue);
    expect(bounds.center, primary.center);
  });
  test("保留负坐标显示器上的有效窗口", () {
    const second = Rect.fromLTWH(-1920, 0, 1920, 1040);
    const saved = Rect.fromLTWH(-1800, 60, 1000, 800);
    expect(restoreWindowsBounds(saved, [primary, second]), saved);
  });
  test("小屏、损坏尺寸与跨边缘窗口都不会恢复到可见区外", () {
    const small = Rect.fromLTWH(0, 0, 720, 500);
    expect(restoreWindowsBounds(null, [small]), small);
    expect(
        restoreWindowsBounds(const Rect.fromLTWH(0, 0, -1, 20), [primary]).size,
        windowsInitialSize);
    final clipped = restoreWindowsBounds(
        const Rect.fromLTWH(1700, 900, 1000, 700), [primary]);
    expect(clipped.right, primary.right);
    expect(clipped.bottom, primary.bottom);
  });
}
