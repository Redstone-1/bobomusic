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

/// 独立待播条目；所有写队列入口统一刷新此 provider。

@ProviderFor(queueEntries)
final queueEntriesProvider = QueueEntriesProvider._();

/// 独立待播条目；所有写队列入口统一刷新此 provider。

final class QueueEntriesProvider extends $FunctionalProvider<
        AsyncValue<List<QueueEntry>>,
        List<QueueEntry>,
        FutureOr<List<QueueEntry>>>
    with $FutureModifier<List<QueueEntry>>, $FutureProvider<List<QueueEntry>> {
  /// 独立待播条目；所有写队列入口统一刷新此 provider。
  QueueEntriesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'queueEntriesProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$queueEntriesHash();

  @$internal
  @override
  $FutureProviderElement<List<QueueEntry>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<QueueEntry>> create(Ref ref) {
    return queueEntries(ref);
  }
}

String _$queueEntriesHash() => r'5b03102ac1ac676dcf36772c16f867fb574e23e1';

/// 最近播放（歌单页；切歌后由页面 invalidate）

@ProviderFor(recentTracks)
final recentTracksProvider = RecentTracksProvider._();

/// 最近播放（歌单页；切歌后由页面 invalidate）

final class RecentTracksProvider extends $FunctionalProvider<
        AsyncValue<List<Track>>, List<Track>, FutureOr<List<Track>>>
    with $FutureModifier<List<Track>>, $FutureProvider<List<Track>> {
  /// 最近播放（歌单页；切歌后由页面 invalidate）
  RecentTracksProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'recentTracksProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$recentTracksHash();

  @$internal
  @override
  $FutureProviderElement<List<Track>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Track>> create(Ref ref) {
    return recentTracks(ref);
  }
}

String _$recentTracksHash() => r'465003af082af60cf7634e75490590d06bff0236';

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
      required String super.argument})
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
    final argument = this.argument as String;
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
    r'fc53a6311a7f2afee8de6a0bf172ae88315e164f';

/// 歌单/我喜欢/本地音乐详情曲目（family 按Playlist 取数）

final class PlaylistDetailTracksFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Track>>, String> {
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
    String playlistId,
  ) =>
      PlaylistDetailTracksProvider._(argument: playlistId, from: this);

  @override
  String toString() => r'playlistDetailTracksProvider';
}
