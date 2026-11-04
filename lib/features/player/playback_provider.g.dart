// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 播放状态机（§5.2-1：PlaySession + NextStrategy；引擎只做"取下一首→装载→播放"）
/// 断点续播：进度去抖 5s 写盘，暂停/切歌/销毁立即写（§5.2-2）

@ProviderFor(Playback)
final playbackProvider = PlaybackProvider._();

/// 播放状态机（§5.2-1：PlaySession + NextStrategy；引擎只做"取下一首→装载→播放"）
/// 断点续播：进度去抖 5s 写盘，暂停/切歌/销毁立即写（§5.2-2）
final class PlaybackProvider
    extends $NotifierProvider<Playback, PlaybackState> {
  /// 播放状态机（§5.2-1：PlaySession + NextStrategy；引擎只做"取下一首→装载→播放"）
  /// 断点续播：进度去抖 5s 写盘，暂停/切歌/销毁立即写（§5.2-2）
  PlaybackProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'playbackProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$playbackHash();

  @$internal
  @override
  Playback create() => Playback();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaybackState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaybackState>(value),
    );
  }
}

String _$playbackHash() => r'c0c3377e0ef044ba73ee78e051e9a6001f1f4356';

/// 播放状态机（§5.2-1：PlaySession + NextStrategy；引擎只做"取下一首→装载→播放"）
/// 断点续播：进度去抖 5s 写盘，暂停/切歌/销毁立即写（§5.2-2）

abstract class _$Playback extends $Notifier<PlaybackState> {
  PlaybackState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PlaybackState, PlaybackState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<PlaybackState, PlaybackState>,
        PlaybackState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
