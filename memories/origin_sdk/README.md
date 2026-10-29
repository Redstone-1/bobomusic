# origin_sdk — 数据源 SDK 记忆（v3）

## 覆盖范围

`lib/origin_sdk/` 下的五个在线音源（bili、kuwo、netease、qq、qianqian）、公共 `origin_types.dart`、歌词链 `lyric/`。五源实例在 `lib/data/origin_service.dart`，歌词实例在 `lyric/lyric_service.dart`，均可替换供测试使用。

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 五源能力与路由、B 站风控恢复/鉴权有效期/cid 补齐、最高可用音质优先与回退、QQ 分页、官方榜单与回退链、文本清洗、歌词链 | 改搜索/取流/签名/榜单/歌词接口前 |
