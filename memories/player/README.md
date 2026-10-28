# player — 播放内核记忆（v3）

## 覆盖范围

`lib/features/player/`：`playback_provider.dart`（状态机）、`audio_engine.dart`/`just_audio_engine.dart`（引擎抽象与实现）、`range_proxy_source.dart`（Range 代理源与缓存）、`play_mode.dart`、`playback_audio_handler.dart`（系统会话）、`lyric_provider.dart`、`mini_player_bar.dart`/`player_card_page.dart`（UI 消费）。旧版 2.7.0 的 `lib/modules/player/` 已退役。

## 索引

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 状态机引用关系、装载/回退链路、乐观写约定、断点续播、测试注入面 | 改任何播放行为之前 |
