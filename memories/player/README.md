# player — 播放内核记忆（v3）

## 覆盖范围

`lib/features/player/`：Playback 状态机、AudioEngine/JustAudioEngine、RangeProxySource、系统会话、播放模式、歌词 controller、迷你条与播放卡。旧版 `lib/modules/player/` 已退役，历史内容见 git。

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 引用关系、五源解析、分阶段回退、恢复与队列、歌词加载、缓存和测试注入 | 改播放、切歌、队列、歌词或系统会话前 |
