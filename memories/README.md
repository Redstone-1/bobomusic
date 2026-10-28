# memories — 模块记忆索引

> 约定见 `.agents/skills/dev_memory/SKILL.md`。本文是总索引；`项目文档.md` 是全景事实源，这里只放**下钻补充**：模块内文件引用关系、易踩坑、易腐字段。
> 记忆文档不会自动加载——新建文档必须登记到所在子目录 `README.md`，新子目录登记到本文件。
> **v3 重写后（2026-10-27 核对）**：旧版 2.7.0 的模块记忆已随退役代码整体重写；旧内容见 git 历史。

## 目录

| 目录 | 覆盖范围 | 什么时候读 |
| --- | --- | --- |
| [player/](./player/README.md) | 播放状态机（Playback/PlaybackDeps）、AudioEngine 与 RangeProxySource 缓存、系统会话、断点续播 | 改播放、切歌、队列、缓存、通知栏行为前 |
| [plaza/](./plaza/README.md) | 广场榜单 Tab（1 真榜+3 主题卡）、搜索合集分流、搜索历史 | 改广场/搜索/合集行为前 |
| [origin_sdk/](./origin_sdk/README.md) | BiliApi/BiliAuth（WBI 签名/风控/playurl）、KuwoApi（第二源/榜单/转义清洗）、歌词三顺位链 | 改搜索、取流、签名、榜单、歌词接口前 |
| [db/](./db/README.md) | bobomusic3.db 四表+play_history、四仓库语义约束、指纹与同步 | 改歌单/收藏/队列/历史存储、写任何 SQL 前 |
| [bugs/](./bugs/README.md) | 缺陷记忆（现象→根因链→修复，MEM-<n>） | 排查相似缺陷时 |

## 不写什么

- 与 `项目文档.md` 大段重复的全景描述
- 逐行代码解读、grep 就能查到的细节
- 薄壳组件的单独立档
