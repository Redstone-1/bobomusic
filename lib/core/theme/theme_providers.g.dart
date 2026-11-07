// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 当前主题色（默认 = 橙色，所有者 2026-11-04 修订；真实持久化）

@ProviderFor(AppThemeSeed)
final appThemeSeedProvider = AppThemeSeedProvider._();

/// 当前主题色（默认 = 橙色，所有者 2026-11-04 修订；真实持久化）
final class AppThemeSeedProvider
    extends $NotifierProvider<AppThemeSeed, AppThemeColor> {
  /// 当前主题色（默认 = 橙色，所有者 2026-11-04 修订；真实持久化）
  AppThemeSeedProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'appThemeSeedProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$appThemeSeedHash();

  @$internal
  @override
  AppThemeSeed create() => AppThemeSeed();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppThemeColor value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppThemeColor>(value),
    );
  }
}

String _$appThemeSeedHash() => r'43e36723d89c26f1ae4e8f1ec7e4dc6f4a7ef47d';

/// 当前主题色（默认 = 橙色，所有者 2026-11-04 修订；真实持久化）

abstract class _$AppThemeSeed extends $Notifier<AppThemeColor> {
  AppThemeColor build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppThemeColor, AppThemeColor>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AppThemeColor, AppThemeColor>,
        AppThemeColor,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}

/// 亮色 ThemeData

@ProviderFor(appLightTheme)
final appLightThemeProvider = AppLightThemeProvider._();

/// 亮色 ThemeData

final class AppLightThemeProvider
    extends $FunctionalProvider<ThemeData, ThemeData, ThemeData>
    with $Provider<ThemeData> {
  /// 亮色 ThemeData
  AppLightThemeProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'appLightThemeProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$appLightThemeHash();

  @$internal
  @override
  $ProviderElement<ThemeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeData create(Ref ref) {
    return appLightTheme(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeData>(value),
    );
  }
}

String _$appLightThemeHash() => r'abb873802b262da86a3dbc442dcd64145a0f338e';

/// 暗色 ThemeData

@ProviderFor(appDarkTheme)
final appDarkThemeProvider = AppDarkThemeProvider._();

/// 暗色 ThemeData

final class AppDarkThemeProvider
    extends $FunctionalProvider<ThemeData, ThemeData, ThemeData>
    with $Provider<ThemeData> {
  /// 暗色 ThemeData
  AppDarkThemeProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'appDarkThemeProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$appDarkThemeHash();

  @$internal
  @override
  $ProviderElement<ThemeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeData create(Ref ref) {
    return appDarkTheme(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeData>(value),
    );
  }
}

String _$appDarkThemeHash() => r'8368186091dc757e208a3d70331dbdc96e83c39b';
