# db — 数据层记忆

## 覆盖范围

`lib/db/db.dart`（BaseDatabaseHelper / DBOrder / DBCollection / 行映射函数）与 `lib/modules/music_order/utils.dart` 的链表重建（`getUpdatedMusicList`）。

## 索引

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 表即歌单模型、行映射、链表重建算法、匹配粒度陷阱 | 改歌单/收藏/待播放存储、写任何 SQL 前 |
