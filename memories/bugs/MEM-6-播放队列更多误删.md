# MEM-6 · 播放队列更多误删

> 核对：2026-10-29，v3 / `64d4a5e` 后的队列菜单修复；依据源码、内存数据库与 widget 回归。未运行应用构建或真机操作。

## 现象与历史根因

- 待播放行的更多按钮直接调用 removeByTrackId，没有弹出菜单；该方法会删除同曲全部排队记录。单条待播或同曲多次排队时，点击更多即清空该曲；旧视图在列表为空时隐藏整个待播分区。
- 下方会话队列的更多按钮只显示“插队/移除在队列引擎批次接入”的占位提示。
- 旧待播行点播也立即按 trackId 全部出队，既混淆重复条目，也无法在取流或装载失败时保留排队记录。单纯改成列表下标仍不可靠：菜单打开期间自动切歌会改变位置。

## 当前关联与处理

| 入口 | 身份与状态 | 行为 |
| --- | --- | --- |
| 播放卡队列按钮 | queue_sheet.dart | 使用既有 AppSheet；更多只打开子菜单，取消不改数据 |
| 待播放 | QueueEntry.id = queue 表主键，track 为歌曲 | 移除本条、下一首播放分别调用 removeEntry / moveEntryToFront；只作用于所选副本 |
| 会话列表 | PlaybackState.queue + queueIndex | 下一首播放加入待播队首；移除按下标和原会话列表引用校验，当前播放条目不提供移除 |
| 待播行点播 | Playback.playQueuedEntry | 回库确认条目存在，插入当前会话之后，装载和播放命令成功后才移除该次排队 |
| 会话行点播 | Playback.playSessionEntry | 使用明确下标，能选择同曲的第二个副本 |

QueueRepository 复用既有 queue.id，未修改 schema。entries / entryById 返回独立 QueueEntry；all 仍返回按顺序的 Track 并保留重复。删除与置顶在事务内按主键定位，位置变化或旧条目已消费不会误操作后继项；失效操作返回 false。

所有入队/出队入口统一刷新 queueEntriesProvider，包括播放卡稍后、搜索、歌单及播放状态机。播放卡稍后等待写入完成再刷新。列表有加载、空态和失败重试，空列表不再通过隐藏分区表示。

会话移除不重新装载引擎；删除当前条目之前的行时修正 queueIndex，立即保存 prefs 并同步系统会话。旧菜单引用的列表已变化或状态正在装载时拒绝按旧下标操作。

_load 的成功仅表示音源已装载且播放命令发出，后续音频错误仍走 errorStream；不能当作整首播放完成。点播失败沿用分阶段回退：源解析失败保留旧曲播放，引擎装载失败恢复旧会话并暂停；待播记录均保留。此保证针对点播入口，自动下一首沿用既有 takeFirst 消费链。

## 回归与排查

- [数据回归](../../test/data/queue_entries_test.dart)：独立主键、重复条目、事务调序、旧 id 和消费后操作。
- [状态机回归](../../test/player/queue_commands_test.dart)：成功后消费一次、失败保留、明确下标点播、会话移除与恢复。
- [菜单回归](../../test/player/queue_sheet_test.dart)：打开/取消不删、嵌套浮层、失效菜单、计数刷新和窄屏放大字号。
- 真实设备上确认更多的点击区域、返回手势、列表滚动和播放衔接；由所有者执行。

实现入口：[队列面板](../../lib/features/player/queue_sheet.dart)、[队列仓库](../../lib/data/repositories/queue_repository.dart)、[播放状态机](../../lib/features/player/playback_provider.dart)。关系图见 [播放地图](../player/00-模块地图.md)、[数据地图](../db/00-模块地图.md)。
