# memories — 模块记忆索引

> 约定见 `.agents/skills/dev_memory/SKILL.md`。本文是总索引；`项目文档.md` 是全景事实源，这里只放**下钻补充**：模块内文件引用关系、易踩坑、易腐字段。
> 记忆文档不会自动加载——新建文档必须登记到所在子目录 `README.md`，新子目录登记到本文件。

## 目录

| 目录 | 覆盖范围 | 什么时候读 |
| --- | --- | --- |
| [player/](./player/README.md) | 播放内核三层（instance/service/model）、音频源与缓存、切歌逻辑 | 改播放、切歌、待播放列表、缓存、通知栏行为前 |
| [origin_sdk/](./origin_sdk/README.md) | BiliClient（WBI 签名/风控票据/playurl）、LyricClient | 改搜索、取流、签名、歌词接口前 |
| [db/](./db/README.md) | sqflite 表结构、表名即歌单名的约束、行映射 | 改歌单/收藏/待播放列表存储前 |
| bugs/ | 缺陷记忆（现象→根因链→修复） | 排查相似缺陷时 |

## 不写什么

- 与 `项目文档.md` 大段重复的全景描述
- 逐行代码解读、grep 就能查到的细节
- 薄壳组件的单独立档
