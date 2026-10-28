# db — 数据层记忆（v3）

## 覆盖范围

`lib/data/db/app_database.dart`（bobomusic3.db v3，四表 + play_history）、`desktop_database.dart`（ffi 引导）、`lib/data/repositories/`（Track/Playlist/Queue/History 四仓库）。旧版 `lib/db/db.dart`「表即歌单」模型与链表重建已退役。

## 索引

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 四表语义约束、upsert 保护字段、分批删除陷阱、播放历史回滚、迁移历史 | 改歌单/收藏/队列/历史存储、写任何 SQL 前 |
