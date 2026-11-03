# player — 播放内核记忆（v3）

## 覆盖范围

`lib/features/player/`：Playback 状态机、AudioEngine/JustAudioEngine、RangeProxySource、系统媒体通道、播放模式、倍速/音量、退出保存、歌词协调、迷你条与共用播放卡。Windows 壳与原生桥见 [desktop](../desktop/README.md)，下载任务见 [download](../download/README.md)。旧版播放器模块已退役，历史内容见 git。

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 状态与失败回退、队列身份、倍速/音量与退出保存、播放卡与桌面共用、歌词协调/居中、VIP 时长探测、系统媒体通道和缓存 | 改播放、切歌、队列、歌词或系统会话前 |
