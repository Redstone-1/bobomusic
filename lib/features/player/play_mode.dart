import "dart:math";

/// 播放模式（§3.4：单曲循环 / 列表循环 / 随机 / 顺序）
/// UI 循环切换按钮按 values 顺序轮转（mock 时代的 modeIndex 0~3 对应同序）
enum PlayMode {
  singleLoop("单曲循环"),
  listLoop("列表循环"),
  shuffle("随机播放"),
  sequential("顺序播放");

  final String label;

  const PlayMode(this.label);

  PlayMode get next => values[(index + 1) % values.length];
}

final _random = Random();

/// 切歌策略纯函数（§5.2-1）：引擎只问"下一首是谁"，不做任何 I/O
///
/// [mode]         当前播放模式
/// [current]      当前曲目在会话队列中的下标（-1 = 无）
/// [queueLength]  会话队列长度
/// [auto]         true = 播完自动触发；false = 用户手动点上一首/下一首
/// [backward]     true = 上一首（仅手动有效；播完自动触发恒为下一首方向）
/// [randomPick]   随机模式下取 0..max-1 的函数（默认 Random；测试注入固定序列）
///
/// 返回目标下标；null = 停止播放（顺序模式到队尾，或队列为空）
int? nextIndex({
  required PlayMode mode,
  required int current,
  required int queueLength,
  required bool auto,
  bool backward = false,
  int Function(int max)? randomPick,
}) {
  if (queueLength <= 0) return null;
  // 单曲循环的"循环"只作用于播完自动触发；手动切换仍按方向移动
  if (auto && mode == PlayMode.singleLoop) {
    return current >= 0 ? current : 0;
  }
  if (mode == PlayMode.shuffle) {
    if (queueLength == 1) return 0;
    final pick = randomPick ?? _random.nextInt;
    var i = pick(queueLength);
    if (i == current) i = (i + 1) % queueLength; // 避免随机到自身
    return i;
  }
  if (mode == PlayMode.listLoop) {
    if (queueLength == 1) return 0;
    final delta = backward ? -1 : 1;
    return (current + delta + queueLength) % queueLength;
  }
  // 顺序播放：手动上一首在队首保持第一首；下一首/播完越过队尾 → 停止
  final target = current + (backward ? -1 : 1);
  if (target < 0) return 0;
  if (target >= queueLength) return null;
  return target;
}
