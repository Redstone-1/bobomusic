// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_tasks.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 已下载列表（数据源 = tracks.downloaded_at；下载完成后由任务层失效）

@ProviderFor(downloadedTracks)
final downloadedTracksProvider = DownloadedTracksProvider._();

/// 已下载列表（数据源 = tracks.downloaded_at；下载完成后由任务层失效）

final class DownloadedTracksProvider extends $FunctionalProvider<
        AsyncValue<List<Track>>, List<Track>, FutureOr<List<Track>>>
    with $FutureModifier<List<Track>>, $FutureProvider<List<Track>> {
  /// 已下载列表（数据源 = tracks.downloaded_at；下载完成后由任务层失效）
  DownloadedTracksProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'downloadedTracksProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$downloadedTracksHash();

  @$internal
  @override
  $FutureProviderElement<List<Track>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Track>> create(Ref ref) {
    return downloadedTracks(ref);
  }
}

String _$downloadedTracksHash() => r'a7cf616ea3efdc542f8ee0d114145750e4a5c62a';

/// 下载任务（内存态，显示在下载管理页的「下载中」）
/// keepAlive：下载在后台进行，页面关闭任务列表不能随之销毁

@ProviderFor(DownloadTasks)
final downloadTasksProvider = DownloadTasksProvider._();

/// 下载任务（内存态，显示在下载管理页的「下载中」）
/// keepAlive：下载在后台进行，页面关闭任务列表不能随之销毁
final class DownloadTasksProvider
    extends $NotifierProvider<DownloadTasks, List<DownloadTask>> {
  /// 下载任务（内存态，显示在下载管理页的「下载中」）
  /// keepAlive：下载在后台进行，页面关闭任务列表不能随之销毁
  DownloadTasksProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'downloadTasksProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$downloadTasksHash();

  @$internal
  @override
  DownloadTasks create() => DownloadTasks();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DownloadTask> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DownloadTask>>(value),
    );
  }
}

String _$downloadTasksHash() => r'f211aafce6f2582b619f59d6c371b2211b2f2910';

/// 下载任务（内存态，显示在下载管理页的「下载中」）
/// keepAlive：下载在后台进行，页面关闭任务列表不能随之销毁

abstract class _$DownloadTasks extends $Notifier<List<DownloadTask>> {
  List<DownloadTask> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<DownloadTask>, List<DownloadTask>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<List<DownloadTask>, List<DownloadTask>>,
        List<DownloadTask>,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
