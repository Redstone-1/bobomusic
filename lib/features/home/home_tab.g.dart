// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_tab.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 当前所在 Tab（IndexedStack 保活各页滚动位置）

@ProviderFor(HomeTabController)
final homeTabControllerProvider = HomeTabControllerProvider._();

/// 当前所在 Tab（IndexedStack 保活各页滚动位置）
final class HomeTabControllerProvider
    extends $NotifierProvider<HomeTabController, HomeTab> {
  /// 当前所在 Tab（IndexedStack 保活各页滚动位置）
  HomeTabControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'homeTabControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$homeTabControllerHash();

  @$internal
  @override
  HomeTabController create() => HomeTabController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeTab>(value),
    );
  }
}

String _$homeTabControllerHash() => r'2a4ada776cf294bc0fc20eb3ffa2cada552e15c4';

/// 当前所在 Tab（IndexedStack 保活各页滚动位置）

abstract class _$HomeTabController extends $Notifier<HomeTab> {
  HomeTab build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HomeTab, HomeTab>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<HomeTab, HomeTab>, HomeTab, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
