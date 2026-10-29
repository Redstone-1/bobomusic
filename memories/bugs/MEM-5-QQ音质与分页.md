# MEM-5 · QQ 免费曲目音质受限被误报 VIP 与分页漏项

> 2026-10-29 核对，本轮修复基于 `11e3126`。接口现场样本支持音质限制与歌曲权限并非一回事；当前自动化使用桩。所有者真机反馈 QQ 仍会受到服务端限制，音质降级与错误分类不保证解除该限制。

## 一句话模型与现象

搜索的免费标记不能保证支持每档音质；过滤后的空页也不能证明原始结果已结束。旧实现固定 M800，空地址一律提示 VIP，并让免费过滤后的空页停止翻页。

## 文件与引用关系

```text
QqApi.search → 原始页/免费过滤/有界补页 → QqSearchResponse(current,hasMore)
    → SearchPage._search/_loadMore → 用最后消费页继续，不因过滤空页终止

QqApi.getMusicUrl → M800 → M500 → C400 → MusicUrl(含 MIME 与备链)
    → 播放/下载链
QqApiError(kind,code,message) → 搜索页/应用壳提示
```

主要文件：`lib/origin_sdk/qq/qq_api.dart`、`lib/origin_sdk/origin_types.dart`、`lib/features/plaza/search_page.dart`。

## 根因与当前约束

1. **MEM-5.1 音质误判**：同一免费条目可能 M800 无 purl，M500 或 C400 有地址。现在按 320kbps MP3 → 128kbps MP3 → AAC 回退，正确透传 audio/mpeg 或 audio/mp4，并保留 CDN 备链。三档都不可用时只说明暂无可播放音质及可能的权限/版权限制，不断言一定需要 VIP。
2. **MEM-5.2 接口失败与空地址混淆**：顶层或模块业务码拒绝、HTTP 拒绝、网络故障、结构变化与音质耗尽分别处理。2001 等服务拒绝直接提示，不当作音质问题连续请求三档。
3. **MEM-5.3 过滤后提前到底**：SDK 每次最多补查三个原始页，返回最后消费页 current 和明确 hasMore。达到补页预算仍没有免费条目时，UI 允许“继续查找”；不足一屏也有“加载更多”。原始页已耗尽才结束。
4. **MEM-5.4 旧搜索响应覆盖新词**：输入变化立即递增请求序号，不能等 300ms 防抖之后再作废；切源取消旧防抖，新搜索清理旧翻页加载态。
5. 搜索响应中的 file.media_mid 可与 song mid 不同，当前会话内有界缓存该映射用于文件名；曲目身份仍为 qq:mid，不另建一首“降音质曲目”。

## 验证与排查

| 症状 | 先查 |
| --- | --- |
| 免费条目提示无地址 | 三档实际 result/purl、media_mid、服务码，不直接认定 VIP |
| 翻页漏掉免费条目 | current 是否为最后消费原始页，hasMore 是否被过滤后长度覆盖 |
| 首屏少量结果无法下翻 | “加载更多”入口与 _loadingMore 防重 |
| QQ 请求受限却显示无结果 | 顶层/模块 code 检查、QqFailure 分类 |
| 切词/切源出现旧结果 | _seq 与防抖取消时机 |

自动化入口：`test/qq/qq_api_test.dart`、`qq_parse_test.dart`、`test/plaza/search_pagination_test.dart`。降音质只选择接口授予的地址，不改变歌曲会员权限。

## 易腐字段与关联

音质文件前缀、服务错误码、免费过滤字段、media_mid、分页元数据与补页预算；同步 [SDK 地图](../origin_sdk/00-模块地图.md) 和 [广场地图](../plaza/00-模块地图.md)。
