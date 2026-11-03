# db — 数据层记忆（v3）

## 覆盖范围

`lib/data/db/app_database.dart`（bobomusic3.db，schema version 6，五表）、`desktop_database.dart`（桌面 ffi）、`lib/data/repositories/`（Track/Playlist/Queue/History）、Windows 固定库位与快照迁移、多目录扫描及安全导入链。旧版“表即歌单”模型已退役。

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | schema v6 五表与迁移、显示覆盖/目录封面、playlistId family、独立队列与事务、Windows 固定库位 | 改歌单/收藏/队列/历史、本地扫描或 SQL 前 |
| [01-本地扫描事件流与扫描舱.md](./01-本地扫描事件流与扫描舱.md) | 多目录配置、隔离扫描事件、不可访问范围保护、同名导入、扫描舱与失败原因 | 改本地扫描、扫描 UI 或失败提示前 |
