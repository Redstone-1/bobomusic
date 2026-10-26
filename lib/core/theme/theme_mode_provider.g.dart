// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 明暗模式：真实持久化（默认亮色，所有者 2026-10-27 指定）

@ProviderFor(AppThemeMode)
final appThemeModeProvider = AppThemeModeProvider._();

/// 明暗模式：真实持久化（默认亮色，所有者 2026-10-27 指定）
final class AppThemeModeProvider
    extends $NotifierProvider<AppThemeMode, ThemeMode> {
  /// 明暗模式：真实持久化（默认亮色，所有者 2026-10-27 指定）
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

String _$appThemeModeHash() => r'829667c5a5f44f4587649000d5093ec59aa16201';

/// 明暗模式：真实持久化（默认亮色，所有者 2026-10-27 指定）

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
