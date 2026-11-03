// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyric_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 歌词控制器（keepAlive）：自动匹配 / 手动搜索替换 / 校准 / 删除
/// 歌词属于曲目（tracks.lyric），写库后所有歌单共享（§3.4-7）

@ProviderFor(LyricController)
final lyricControllerProvider = LyricControllerProvider._();

/// 歌词控制器（keepAlive）：自动匹配 / 手动搜索替换 / 校准 / 删除
/// 歌词属于曲目（tracks.lyric），写库后所有歌单共享（§3.4-7）
final class LyricControllerProvider
    extends $NotifierProvider<LyricController, LyricState> {
  /// 歌词控制器（keepAlive）：自动匹配 / 手动搜索替换 / 校准 / 删除
  /// 歌词属于曲目（tracks.lyric），写库后所有歌单共享（§3.4-7）
  LyricControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'lyricControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$lyricControllerHash();

  @$internal
  @override
  LyricController create() => LyricController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LyricState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LyricState>(value),
    );
  }
}

String _$lyricControllerHash() => r'8c58c215bed8848a3a36f0377f727320f07118dc';

/// 歌词控制器（keepAlive）：自动匹配 / 手动搜索替换 / 校准 / 删除
/// 歌词属于曲目（tracks.lyric），写库后所有歌单共享（§3.4-7）

abstract class _$LyricController extends $Notifier<LyricState> {
  LyricState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LyricState, LyricState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<LyricState, LyricState>, LyricState, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
