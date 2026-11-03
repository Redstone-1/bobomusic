# desktop — Windows 桌面记忆（v3）

## 覆盖范围

Windows 应用壳、窗口生命周期、固定数据目录、桌面播放布局、SMTC 原生桥、图标及打包。当前 `usesDesktopLayout` 只对 Windows 开启；Linux 联调和 macOS 图标同步不代表这些平台已完成桌面适配。

| 文档 | 覆盖主题 | 什么时候读 |
| --- | --- | --- |
| [00-模块地图.md](./00-模块地图.md) | 启动/关闭链、页面保留、歌词布局、系统媒体线程桥、数据与发布边界 | 改 Windows 启动、窗口、桌面布局、原生媒体控制或分发前 |

播放状态见 [player](../player/README.md)，数据与扫描见 [db](../db/README.md)，下载见 [download](../download/README.md)，操作清单见 [Windows 发布与验收](../../windows/发布与验收.md)。
