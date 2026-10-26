import "dart:async";

import "package:just_audio/just_audio.dart";

import "audio_engine.dart";
import "range_proxy_source.dart";

/// just_audio 引擎（真实现）：桌面解码走 media_kit 后端
/// （main 里 JustAudioMediaKit.ensureInit，Android 用平台默认解码器）
///
/// 网络 B 站直链走 [RangeProxySource]（Range 直取/看门狗/降级/落盘缓存），
/// 本地文件直读；事件流一一映射到 just_audio 对应流
class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration> get durationStream => _player.durationStream.map(
        (d) => d ?? Duration.zero,
      );

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completionStream => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Object> get errorStream => _player.errorStream;

  @override
  Future<void> load(PlaySource source, {Duration? initialPosition}) async {
    final AudioSource audioSource = source.isLocal
        ? AudioSource.file(source.url)
        : RangeProxySource(
            key: source.key,
            url: source.url,
            backupUrl: source.backupUrl,
            headers: source.headers,
            contentType: source.contentType,
          );
    await _player.setAudioSource(audioSource, initialPosition: initialPosition);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
