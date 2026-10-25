import "dart:async";

/// 播放引擎抽象（§5.2-1）：Playback 状态机只依赖本接口
/// - 真实现（A2）：just_audio + audio_service（通知栏/耳机），桌面走 media_kit 后端
/// - 测试实现：FakeEngine（test/helpers，时间可控、无平台通道）
///
/// 引擎只管"装载/播放/暂停/seek/事件流"，不持有曲目语义（队列与切歌在状态机）
abstract class AudioEngine {
  /// 播放进度（高频流，UI 侧用 select 消费）
  Stream<Duration> get positionStream;

  /// 总时长（未就绪时为 Duration.zero）
  Stream<Duration> get durationStream;

  /// 播放中标志
  Stream<bool> get playingStream;

  /// 播完一首（触发状态机按模式切歌）
  Stream<void> get completionStream;

  /// 装载错误（网络/解码失败；状态机 toast 提示并按模式跳下一首）
  Stream<Object> get errorStream;

  /// 装载音频源。[initialPosition] 供断点续播跳过前缀
  Future<void> load(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  Future<void> dispose();
}
