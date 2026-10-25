import "package:bobomusic/features/player/play_mode.dart";
import "package:flutter_test/flutter_test.dart";

/// §5.2-1：NextStrategy 全矩阵单测（四模式 × 队列空/单元素/首/中/尾 × 自动/手动 × 前后向）
void main() {
  group("空队列", () {
    for (final mode in PlayMode.values) {
      test("${mode.label}：任何触发都停止", () {
        expect(
          nextIndex(mode: mode, current: -1, queueLength: 0, auto: true),
          isNull,
        );
        expect(
          nextIndex(mode: mode, current: 0, queueLength: 0, auto: false),
          isNull,
        );
      });
    }
  });

  group("单曲循环（auto 只回到自身，手动按方向移动）", () {
    test("播完 → 同曲重播", () {
      expect(
        nextIndex(mode: PlayMode.singleLoop, current: 1, queueLength: 3, auto: true),
        1,
      );
    });
    test("手动下一首/上一首正常移动", () {
      expect(
        nextIndex(mode: PlayMode.singleLoop, current: 1, queueLength: 3, auto: false),
        2,
      );
      expect(
        nextIndex(mode: PlayMode.singleLoop, current: 1, queueLength: 3, auto: false, backward: true),
        0,
      );
    });
  });

  group("列表循环（环形，无尽头）", () {
    test("队尾下一首绕回队首", () {
      expect(
        nextIndex(mode: PlayMode.listLoop, current: 2, queueLength: 3, auto: true),
        0,
      );
    });
    test("队首上一首绕回队尾", () {
      expect(
        nextIndex(mode: PlayMode.listLoop, current: 0, queueLength: 3, auto: false, backward: true),
        2,
      );
    });
    test("单元素队列恒为 0", () {
      expect(
        nextIndex(mode: PlayMode.listLoop, current: 0, queueLength: 1, auto: true),
        0,
      );
    });
  });

  group("随机（注入固定序列断言）", () {
    test("命中当前曲时避开到下一首", () {
      // 固定 pick=1：current=1 时避开到 2
      expect(
        nextIndex(mode: PlayMode.shuffle, current: 1, queueLength: 3, auto: true, randomPick: (_) => 1),
        2,
      );
    });
    test("未命中当前曲直接采用", () {
      expect(
        nextIndex(mode: PlayMode.shuffle, current: 0, queueLength: 3, auto: false, randomPick: (_) => 1),
        1,
      );
    });
    test("单元素队列恒为 0（无处可避）", () {
      expect(
        nextIndex(mode: PlayMode.shuffle, current: 0, queueLength: 1, auto: true, randomPick: (_) => 0),
        0,
      );
    });
  });

  group("顺序播放（到队尾停止）", () {
    test("播完队尾 → 停止", () {
      expect(
        nextIndex(mode: PlayMode.sequential, current: 2, queueLength: 3, auto: true),
        isNull,
      );
    });
    test("手动下一首到队尾 → 停止", () {
      expect(
        nextIndex(mode: PlayMode.sequential, current: 2, queueLength: 3, auto: false),
        isNull,
      );
    });
    test("手动上一首在队首 → 保持第一首", () {
      expect(
        nextIndex(mode: PlayMode.sequential, current: 0, queueLength: 3, auto: false, backward: true),
        0,
      );
    });
    test("中部正常前进", () {
      expect(
        nextIndex(mode: PlayMode.sequential, current: 1, queueLength: 3, auto: true),
        2,
      );
    });
  });

  test("PlayMode 循环轮转顺序（与 mock 时代 modeIndex 0~3 一致）", () {
    expect(PlayMode.values.map((m) => m.name).toList(), [
      "singleLoop",
      "listLoop",
      "shuffle",
      "sequential",
    ]);
    expect(PlayMode.listLoop.next, PlayMode.shuffle);
    expect(PlayMode.sequential.next, PlayMode.singleLoop);
  });
}
