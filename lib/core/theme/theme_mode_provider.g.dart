// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 明暗模式
/// S1.1 为 codegen 冒烟骨架（默认暗色，贴合风格 A 的沉浸式基调）；
/// S3.1 接入 SharedPreferences 真实持久化

@ProviderFor(AppThemeMode)
final appThemeModeProvider = AppThemeModeProvider._();

/// 明暗模式
/// S1.1 为 codegen 冒烟骨架（默认暗色，贴合风格 A 的沉浸式基调）；
/// S3.1 接入 SharedPreferences 真实持久化
final class AppThemeModeProvider
    extends $NotifierProvider<AppThemeMode, ThemeMode> {
  /// 明暗模式
  /// S1.1 为 codegen 冒烟骨架（默认暗色，贴合风格 A 的沉浸式基调）；
  /// S3.1 接入 SharedPreferences 真实持久化
  AppThemeModeProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'appThemeModeProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$appThemeModeHash();

  @$internal
  @override
  AppThemeMode create() => AppThemeMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$appThemeModeHash() => r'75981f79c278bca1c07f87f879a741034340c1fa';

/// 明暗模式
/// S1.1 为 codegen 冒烟骨架（默认暗色，贴合风格 A 的沉浸式基调）；
/// S3.1 接入 SharedPreferences 真实持久化

abstract class _$AppThemeMode extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ThemeMode, ThemeMode>, ThemeMode, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
