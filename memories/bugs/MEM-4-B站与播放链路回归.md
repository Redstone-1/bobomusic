# MEM-4 · B 站风控与公共播放链路回归

> 2026-10-29 核对，本轮修复基于 `11e3126`。本地桩、HTTP 服务与播放器契约测试覆盖以下结论；所有者已做真机回归，反馈本轮接口整体较稳定。后台与通知栏行为未逐项记录。

## 一句话模型与历史现象

“搜索失败/播放失败”可发生在鉴权、API 响应、CDN 字节流或引擎状态四层，不能只用 playurl 是否返回地址判断。v3 曾出现风控响应误解析、会话材料永不过期、Range 多一个字节、断流被吞和暂停状态被迟到 Future 覆盖。

## 入口与文件关系

```text
BiliAuth.ensure/refresh → BiliApi._query → MusicUrl
    → Playback._resolveSource → JustAudioEngine → RangeProxySource
    → 引擎错误流 → Playback 标记源失效/清 loadedKey → 应用壳提示并清 error
    → 用户重试 → 失效标记仍在 → 跳过旧直链缓存重新解析
```

核心文件为 `lib/origin_sdk/bili/bili_auth.dart`、`bili_api.dart`，以及 `lib/features/player/` 下的 `range_proxy_source.dart`、`just_audio_engine.dart`、`playback_provider.dart`。

## 已确认根因与当前修复

1. **MEM-4.1 风控漏判**：服务端可返回 code=0 + data.v_voucher。现在 voucher 独立识别为 BiliApiRejectError；风控、签名失效与 HTTP 412 最多重刷鉴权并重新签名一次，429 和普通业务错误不循环重试。解析结构变化归一为 BiliParseError。
2. **MEM-4.2 会话缓存不失效**：旧 _ready 只看字段非空。现在内存和 prefs 都按实际 24 小时有效期检查，支持时钟注入；refresh 跳过旧缓存并合并并发。主页 cookie 暂不可得时用 spi 继续匿名鉴权。
3. **MEM-4.3 Range 契约错误**：just_audio 的 end 排尾，HTTP Range 尾字节含尾；当前发请求时减一，文件缓存按排尾读。上游忽略 Range 返回 200 时，按整曲总长裁掉前缀，而非伪造带偏移的总长。
4. **MEM-4.4 断流被缓存代码吞掉**：当前区分缓存 I/O 与上游错误。主链断流从已交付字节处续接备用链；总长不一致拒绝拼接。无备链则向下游报错；只有完整字节转正缓存，缓存写失败仍可播放。
5. **MEM-4.5 播放生命周期误作启动确认**：AudioPlayer.play 的 Future 到暂停/结束才完成。JustAudioEngine.play 只确认命令已发出，后续失败通过 errorStream；代次隔离旧播放 Future 的迟到错误，避免污染切曲或暂停后的会话。
6. **MEM-4.6 提示清错不等于源已恢复**：Playback 的 _failedSourceKey 独立于 UI error；运行时错误清 _loadedKey，下一次装载失败曲时强制重新解析 B 站直链，不能因 toast 已清错而复用旧 URL。

## 回归与排查

| 症状 | 先查 |
| --- | --- |
| 空结果里出现 v_voucher / 解析异常 | BiliApi 的独立风控判定、重刷次数 |
| 运行较久后搜索持续失败 | BiliAuth 的有效期、refresh 是否绕过旧缓存 |
| seek 数据长度不符 | request(start,end) 排尾，200/206 的不同裁剪路径 |
| 断流不报错或缓存只有半首 | _resumeStream、_teeToCache 的错误传播与完整性判定 |
| 暂停后又显示在播 | JustAudioEngine.play 是否等待生命周期、旧 Future 代次 |
| 报错提示消失后重试仍失败 | _failedSourceKey、_loadedKey 和 forceRefresh |

测试入口：`test/bili/bili_recovery_test.dart`、`bili_auth_cache_test.dart`，`test/player/range_proxy_source_test.dart`、`just_audio_engine_test.dart`、`playback_provider_test.dart`。不要再用立即完成的 FakeEngine.play 或含尾 Range 样例代替真实库契约。

## 易腐字段与关联

有效期、可恢复业务码、直链缓存策略、Range 元数据、引擎 Future 契约、_failedSourceKey；改动时更新 [SDK 地图](../origin_sdk/00-模块地图.md) 与 [播放地图](../player/00-模块地图.md)。
