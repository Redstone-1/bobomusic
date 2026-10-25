// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 明暗模式：S3.1 起真实持久化（默认暗色，贴合风格 A 沉浸基调）

@ProviderFor(AppThemeMode)
final appThemeModeProvider = AppThemeModeProvider._();

/// 明暗模式：S3.1 起真实持久化（默认暗色，贴合风格 A 沉浸基调）
final class AppThemeModeProvider
    extends $NotifierProvider<AppThemeMode, ThemeMode> {
  /// 明暗模式：S3.1 起真实持久化（默认暗色，贴合风格 A 沉浸基调）
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

String _$appThemeModeHash() => r'd433892de3a23e6f8197af691c612d0e301d8538';

/// 明暗模式：S3.1 起真实持久化（默认暗色，贴合风格 A 沉浸基调）

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
