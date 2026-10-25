// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mock_playback.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MockPlayback)
final mockPlaybackProvider = MockPlaybackProvider._();

final class MockPlaybackProvider
    extends $NotifierProvider<MockPlayback, MockPlaybackState> {
  MockPlaybackProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'mockPlaybackProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$mockPlaybackHash();

  @$internal
  @override
  MockPlayback create() => MockPlayback();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MockPlaybackState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MockPlaybackState>(value),
    );
  }
}

String _$mockPlaybackHash() => r'957916e76801360717953c7343f861eaecf8795f';

abstract class _$MockPlayback extends $Notifier<MockPlaybackState> {
  MockPlaybackState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MockPlaybackState, MockPlaybackState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<MockPlaybackState, MockPlaybackState>,
        MockPlaybackState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
