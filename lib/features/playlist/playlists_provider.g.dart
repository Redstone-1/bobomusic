// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlists_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 歌单目录（歌单页真数据源）：加载 + CRUD（每次变更后重载目录）

@ProviderFor(Playlists)
final playlistsProvider = PlaylistsProvider._();

/// 歌单目录（歌单页真数据源）：加载 + CRUD（每次变更后重载目录）
final class PlaylistsProvider
    extends $AsyncNotifierProvider<Playlists, List<Playlist>> {
  /// 歌单目录（歌单页真数据源）：加载 + CRUD（每次变更后重载目录）
  PlaylistsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'playlistsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$playlistsHash();

  @$internal
  @override
  Playlists create() => Playlists();
}

String _$playlistsHash() => r'edca1346415727087cc644fbdd470e8b29ad9d57';

/// 歌单目录（歌单页真数据源）：加载 + CRUD（每次变更后重载目录）

abstract class _$Playlists extends $AsyncNotifier<List<Playlist>> {
  FutureOr<List<Playlist>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Playlist>>, List<Playlist>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<List<Playlist>>, List<Playlist>>,
        AsyncValue<List<Playlist>>,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}

/// 我喜欢数量（快捷卡计数）

@ProviderFor(likedCount)
final likedCountProvider = LikedCountProvider._();

/// 我喜欢数量（快捷卡计数）

final class LikedCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// 我喜欢数量（快捷卡计数）
  LikedCountProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'likedCountProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$likedCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return likedCount(ref);
  }
}

String _$likedCountHash() => r'2ecbe4dbf39e0108a0af5c4cee3cb9996a7b5b20';

/// 本地音乐数量（快捷卡计数；C3 本地扫描后填充）

@ProviderFor(localCount)
final localCountProvider = LocalCountProvider._();

/// 本地音乐数量（快捷卡计数；C3 本地扫描后填充）

final class LocalCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// 本地音乐数量（快捷卡计数；C3 本地扫描后填充）
  LocalCountProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'localCountProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$localCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return localCount(ref);
  }
}

String _$localCountHash() => r'094d4c6728e187468f41d9e884b093a534ab7ccf';

/// 播放队列曲目（歌单页队列区；S4 播放内核填充数据）

@ProviderFor(queueTracks)
final queueTracksProvider = QueueTracksProvider._();

/// 播放队列曲目（歌单页队列区；S4 播放内核填充数据）

final class QueueTracksProvider extends $FunctionalProvider<
        AsyncValue<List<Track>>, List<Track>, FutureOr<List<Track>>>
    with $FutureModifier<List<Track>>, $FutureProvider<List<Track>> {
  /// 播放队列曲目（歌单页队列区；S4 播放内核填充数据）
  QueueTracksProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'queueTracksProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$queueTracksHash();

  @$internal
  @override
  $FutureProviderElement<List<Track>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Track>> create(Ref ref) {
    return queueTracks(ref);
  }
}

String _$queueTracksHash() => r'6a7f37c551c6edebcd633fcb8112ae550d073e0d';

/// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）

@ProviderFor(playlistDetailTracks)
final playlistDetailTracksProvider = PlaylistDetailTracksFamily._();

/// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）

final class PlaylistDetailTracksProvider extends $FunctionalProvider<
        AsyncValue<List<Track>>, List<Track>, FutureOr<List<Track>>>
    with $FutureModifier<List<Track>>, $FutureProvider<List<Track>> {
  /// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）
  PlaylistDetailTracksProvider._(
      {required PlaylistDetailTracksFamily super.from,
      required Playlist super.argument})
      : super(
          retry: null,
          name: r'playlistDetailTracksProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$playlistDetailTracksHash();

  @override
  String toString() {
    return r'playlistDetailTracksProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Track>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Track>> create(Ref ref) {
    final argument = this.argument as Playlist;
    return playlistDetailTracks(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaylistDetailTracksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$playlistDetailTracksHash() =>
    r'7a8de976e5fa29525cb8a9e953ea399c9185f558';

/// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）

final class PlaylistDetailTracksFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Track>>, Playlist> {
  PlaylistDetailTracksFamily._()
      : super(
          retry: null,
          name: r'playlistDetailTracksProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  /// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）

  PlaylistDetailTracksProvider call(
    Playlist playlist,
  ) =>
      PlaylistDetailTracksProvider._(argument: playlist, from: this);

  @override
  String toString() => r'playlistDetailTracksProvider';
}

/// 收藏合集（广场合集区；收藏动作落库后 invalidate）

@ProviderFor(collections)
final collectionsProvider = CollectionsProvider._();

/// 收藏合集（广场合集区；收藏动作落库后 invalidate）

final class CollectionsProvider extends $FunctionalProvider<
        AsyncValue<List<Playlist>>, List<Playlist>, FutureOr<List<Playlist>>>
    with $FutureModifier<List<Playlist>>, $FutureProvider<List<Playlist>> {
  /// 收藏合集（广场合集区；收藏动作落库后 invalidate）
  CollectionsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'collectionsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$collectionsHash();

  @$internal
  @override
  $FutureProviderElement<List<Playlist>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Playlist>> create(Ref ref) {
    return collections(ref);
  }
}

String _$collectionsHash() => r'de00d754549dc1fe05ede9813f5154493ba214d9';
