// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'singers_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(hotSingers)
final hotSingersProvider = HotSingersProvider._();

final class HotSingersProvider extends $FunctionalProvider<
        AsyncValue<List<SingerEntry>>,
        List<SingerEntry>,
        FutureOr<List<SingerEntry>>>
    with
        $FutureModifier<List<SingerEntry>>,
        $FutureProvider<List<SingerEntry>> {
  HotSingersProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'hotSingersProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$hotSingersHash();

  @$internal
  @override
  $FutureProviderElement<List<SingerEntry>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<SingerEntry>> create(Ref ref) {
    return hotSingers(ref);
  }
}

String _$hotSingersHash() => r'9ed9d02ca6ec505cdadad75df7b25fc3574432fb';
