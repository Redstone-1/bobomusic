# player — 播放内核记忆

## 覆盖范围

`lib/modules/player/` 中的内核部分：`instance.dart`（BBPlayer）、`service.dart`（AudioPlayerHandler）、`model.dart`（PlayerModel）、`source.dart`（BBMusicSource）、`const.dart`、`utils.dart`。UI 部分（`player_card/`、`lyrics_card/`、`player.dart`、`list.dart`）只在涉及内核交互时提及。

## 索引

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 三层引用关系、切歌决策链、待播放列表插队机制、事件流 | 改任何播放行为之前 |
