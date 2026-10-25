import "package:bobomusic/origin_sdk/origin_types.dart" as sdk;

import "models/track.dart" as models;

/// SDK MusicItem → UI 曲目（S3 起搜索/歌单数据统一走此映射）
/// 注意：SDK 与 UI 各有一套 OriginType，且 SDK 枚举自带 name 字段（"哔哩哔哩"），
/// 桥接必须按 value（"bili"/"youTube"/"local"）匹配，缺失值回退 bili
extension MusicItemMapper on sdk.MusicItem {
  models.Track toTrack() => models.Track(
        id: id,
        name: name,
        author: author,
        cover: cover.isEmpty ? null : cover,
        duration: duration,
        origin: _mapOrigin(origin),
      );
}

/// SDK 曲目列表映射
List<models.Track> musicItemsToTracks(List<sdk.MusicItem> items) =>
    [for (final m in items) m.toTrack()];

/// SearchItem → UI 曲目（单曲优先取 musicList 首条播放 id，回退条目自身）
extension SearchItemMapper on sdk.SearchItem {
  models.Track toTrack() {
    final list = musicList;
    if (list != null && list.isNotEmpty) return list.first.toTrack();
    return models.Track(
      id: id,
      name: name,
      author: author,
      cover: cover.isEmpty ? null : cover,
      duration: duration,
      origin: _mapOrigin(origin),
    );
  }
}

models.OriginType _mapOrigin(sdk.OriginType origin) =>
    models.OriginType.values.firstWhere(
      (o) => o.name == origin.value,
      orElse: () => models.OriginType.bili,
    );
