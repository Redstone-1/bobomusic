# MEM-1 · B 站合集条目被当单曲直接播放

## 现象

B 站音源搜索结果点合集类条目：直接报「播放失败：取流失败/-404」，不进列表页；列表上也没有任何合集标识。

## 根因链

1. `search_type=video` 返回的卡片 JSON **不携带合集标记**——多P 视频有 `videos/pages`（type=orderName 可判），UGC 合集只有 `is_season_display`/`ugc_season`，`BiliSearchItem.fromJson` 解析出的 `type` 为 null。
2. 搜索页按 `type==orderName || musicList>1` 分流，null type 落进单曲分支 → `toTrack()` 拿合集 id（无 cid）走 playurl → 必然失败。
3. 2.7.0 的正确做法（git master `lib/modules/music_plaza/search/search.dart`）：**列表行不判合集**，任何条目点击先 `searchDetail`（view 接口）拉详情，再用详情的 `type`/`isSeasonDisplay` 分流。

## 修复（a9efa1a）

- 搜索页 `_playWithResolve`：点击 → searchDetail → `orderName` 多P / `isSeasonDisplay` → `searchSeason(mid, seasonId)` 拉成员 → 合集列表页；真单曲才播放；酷我短路直播（无合集概念）。
- `types.dart`：season 条目仍解析为 orderName（兜底）。
- 合集行整包操作（收藏/全部加入待播放/全部下载）共用 `_fetchCollectionTracks`。
- 测试：`test/bili/search_item_type_test.dart` 锁四种条目形状。

## 为何容易复发

列表阶段**无法**从卡片数据识别 UGC 合集（接口限制，2.7.0 同样如此）。任何"在列表行按 type 分流播放"的重构都会重新引入此缺陷。

## 关联

[[../plaza/00-模块地图]] · [[../origin_sdk/00-模块地图]]
