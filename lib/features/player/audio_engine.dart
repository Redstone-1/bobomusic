import "dart:async";

/// 装载源描述：网络直链（含降级链/请求头）或本地文件
class PlaySource {
  /// 曲目身份（缓存文件 key；origin-id）
  final String key;
  final String url;

  /// 备用直链（主链失败降级）
  final String? backupUrl;

  /// 请求头（B 站 CDN 必须带 Referer）
  final Map<String, String>? headers;

  /// true = [url] 是本地文件路径，直读不走网络
  final bool isLocal;

  const PlaySource({
    required this.key,
    required this.url,
    this.backupUrl,
    this.headers,
    this.isLocal = false,
  });
}

/// 播放引擎抽象（§5.2-1）：Playback 状态机只依赖本接口
/// - 真实现：JustAudioEngine（just_audio；桌面 media_kit 后端，A2）
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

  /// 装载/播放错误（网络/解码失败；状态机 toast 提示并按模式跳下一首）
  Stream<Object> get errorStream;

  /// 装载音频源。[initialPosition] 供断点续播跳过前缀
  Future<void> load(PlaySource source, {Duration? initialPosition});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  Future<void> dispose();
}
