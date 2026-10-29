# db — 数据层记忆（v3）

## 覆盖范围

`lib/data/db/app_database.dart`（bobomusic3.db，schema version 3，五表）、`desktop_database.dart`（桌面 ffi）、`lib/data/repositories/`（Track/Playlist/Queue/History）、本地扫描与导入链。旧版“表即歌单”模型已退役。

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 五表关系、upsert 保护字段、指纹同步与增量导入、独立队列条目与事务、历史回滚和迁移边界 | 改歌单/收藏/队列/历史、本地扫描或 SQL 前 |
