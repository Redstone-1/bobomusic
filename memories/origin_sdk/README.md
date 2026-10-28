# origin_sdk — 数据源 SDK 记忆（v3）

## 覆盖范围

`lib/origin_sdk/`：`origin_types.dart`（OriginService 抽象与数据类型）、`bili/`（bili_api / bili_auth / bili_api_error / sign / ticket / types，S2 拆分后结构）、`kuwo/kuwo_api.dart`（第二源 + 榜单解析）、`lyric/`（三顺位歌词链）。全局单例在 `lib/data/origin_service.dart`。旧 BiliClient 单体（client.dart）已拆分退役。

## 索引

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 双音源结构、鉴权生命周期、playurl/取流、榜单数据源实测结论、转义清洗约定 | 改搜索/取流/签名/票据/榜单/歌词接口前 |
