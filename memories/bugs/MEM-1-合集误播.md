# MEM-1 · B 站合集条目被当单曲直接播放

> 当前约束核对：2026-10-29，`6d27559`。保留原缺陷背景；SDK 缺 cid 行为已随之后实现变化。

## 历史现象与根因

搜索结果中的合集被当单曲直接播放，出现取流失败/-404，且不进入列表。

1. search_type=video 的卡片不保证携带 UGC 合集信息，不能仅按卡片 type 或 musicList 长度判断。
2. 当时单曲分支把无 cid 的合集 ID 交给 playurl，取流阶段无法补齐而失败。
3. 搜索页需要先请求 view 详情，再按多 P、UGC 合集或真单曲分流；单靠 ID 可取流也不能表达合集导航语义。

## 原修复与当前实现

原修复提交 `a9efa1a`：

- `lib/features/plaza/search_page.dart` 的 _playWithResolve：B 站点击先 searchDetail，多 P 进入列表，UGC 合集通过 searchSeason 拉成员，真单曲才播放。
- 当前非 B 站的四个源按单曲直接播放，不调用 B 站特有详情/合集接口。
- _fetchCollectionTracks 为打开、整包入队、整包下载复用成员解析。
- `test/bili/search_item_type_test.dart` 验证响应条目类型，应用级行为见 `test/widget_test.dart`。

2026-10-30 追加（所有者真机复测驱动）：

- 喜欢与更多菜单曾绕过详情分流，合集（含被判成单曲类型的聚合卡）以歌曲身份入库：现点击、喜欢、更多菜单共用 _resolveBiliEntry 分流；合集按所有者语义处理——喜欢=成员全部入库喜欢，加入歌单/待播放/下载按整包（收藏合集功能已删除，旧 collection 歌单行由 v4 迁移清除）。

后续 `lib/origin_sdk/bili/bili_api.dart` 的 getMusicUrl 已增加缺 cid 自愈：请求详情，取首个可播 P 的 ID 补齐 cid；仍缺失才抛 BiliInvalidIdError。**“缺 cid 必然取流失败”已不是当前结论。**

## 仍需保持的约束

cid 自愈用于搜索旧 ID、队列和已存曲目的取流容错，不能替代合集分流。若只依赖自愈直接播放，可能只播第一 P 而跳过应有的合集列表。列表卡片数据不足时，仍须通过详情识别内容类型。

一切"把条目当单曲处理"的入口（播放、喜欢等）都必须经详情分流；卡片 type=music 也不可信——videos=1 的合集聚合卡会被判成单曲类型，2026-10-30 真机复测实证。

## 关联

[广场地图](../plaza/00-模块地图.md) · [SDK 地图](../origin_sdk/00-模块地图.md)
