# MEM-3 · 酷我歌手名残留 Unicode 转义或反斜杠

> 当前出口核对：2026-10-29，`6d27559`；未重放线上原始响应或清洗存量用户库。

## 历史现象与根因

部分歌手名残留 Unicode 转义；第一版修复后仍残留反斜杠。

- 早期缺陷主要来自榜单 SSR 的可见文本：不经过 JSON 解码，可能残留一层或多层 JS 转义。
- 原 decodeKuwoText 只处理 HTML 实体；第一次仅消费一道反斜杠，遇到双重转义会留下反斜杠。
- JSON 解码能去掉结构层转义，但不保证响应字符串没有嵌套转义；不能将“JSON 链永不泄漏”作为新增出口的前提。

## 修复与当前出口

原修复提交 `ffb6614`：

- `lib/origin_sdk/kuwo/kuwo_api.dart` 的 decodeKuwoText 复用 _decodeJsEscapes，兼容连续多道反斜杠及转义斜杠。
- 封面 URL 的 _unescapeJsString 复用同一解码逻辑。
- 当前官方 bang JSON、搜索与 SSR 等文本出口继续统一清洗；增加解析分支时不能自建不兼容的替代规则。
- `test/kuwo/kuwo_parse_test.dart` 覆盖转义与字段路径，`test/kuwo/bang_chart_test.dart` 覆盖官方榜解析。

## 存量边界

清洗发生在 SDK 解析出口，不会自动全表重写已经入库的内容。曲目再次经过清洗后的 upsert（如重播/收藏）时，author 等内容字段才会更新。本轮未新增存量迁移或全库清洗。

## 关联

[SDK 地图](../origin_sdk/00-模块地图.md) · [数据地图](../db/00-模块地图.md)
