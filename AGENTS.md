# AGENTS.md — 啵啵音乐 AI 开发约定

> 所有 AI agent（主会话 / 子 agent / 排查 / 评审）动手改本仓库前，先读本文。
> 本文是**约定入口**，不是知识全文；知识分层见文末「知识源地图」。

## 项目是什么

- 单仓库 Flutter 音乐 App（`com.bobomusic`），当前版本 2.7.0，Flutter 3.27.1 / Dart >=3.3.1 / JDK 17。
- **无后端**：音源来自 Bilibili 逆向接口（`lib/origin_sdk/bili/`），歌词/封面来自第三方代理（`lib/origin_sdk/lyric/`），用户数据全部本地（sqflite + SharedPreferences）。
- 正式发布平台 Android；Windows/Linux 桌面可运行；iOS/macOS/Web 未适配。
- 上游基于 [bbmusic](https://github.com/bb-music/flutter-app) 二次开发。

## 常用命令

```bash
flutter pub get
flutter analyze          # 改动后必须跑，要求 0 error（基线见下）
flutter test             # 纯 Dart 单测，不依赖设备/网络
flutter run -d windows   # 桌面联调
flutter build apk        # Android 发布（需 android/key.properties 签名）
```

- 环境/签名/真机调试见 `安卓开发指南.md`。
- **禁止在验证前提交**；不擅自 `git stage/commit/push/revert`。

## 目录速览

```
lib/
├── main.dart                  # 入口：AudioService.init → 清待播放表 → 主题 → MultiProvider
├── modules/
│   ├── home/  tabbar/         # 首页骨架与三 Tab 导航
│   ├── music_order/           # 歌单模块（utils.dart 的 getUpdatedMusicList 是列表读取唯一入口）
│   ├── music_plaza/           # 广场：搜索、热门歌手、收藏合集
│   ├── player/                # 播放内核（instance/service/model/source）+ 全部播放 UI
│   ├── setting/  download/    # 设置 / 下载
├── origin_sdk/                # BiliClient（WBI 签名+票据+playurl）、LyricClient
├── db/db.dart                 # sqflite：DBOrder / DBCollection + 行映射函数
├── event_bus/event_bus.dart   # 全局事件（11 个事件类）
├── components/ constants/ utils/ permission/ icons/
```

## 硬规则（违反即返工）

0. **动工红线（用户全局规则，优先级最高，全文见 `~/.zcode/AGENTS.md`）**：
   - 不替用户做决定——方案给选项与建议，选择权在用户；
   - 任何需求先出方案设计与开发计划，**经用户允许再动工**（用户给出明确执行方案/执行信号时除外）；
   - 改动代码后**不执行 build**，`flutter run`、真机验证等手动验证一律交由用户；
   - **不执行 `git add` / `git commit`**（`push` / `revert` 同样禁止），版本操作全部由用户手动完成；
   - **所有技术方案必须经过用户同意；必须经过用户采纳后才能同步文档**（含 `重构计划.md`、`memories/`、各 README——未采纳的方案只能出现在对话里，不得落盘成"已定"内容）。
1. **跨模块通信**只走 `lib/event_bus/event_bus.dart` 的事件，不新增模块间直接 import。
2. **歌单数据读取**统一走 `getUpdatedMusicList`（`lib/modules/music_order/utils.dart`），它负责去重 + prev/next 链表重建。
3. **表名即歌单名**（中文表名，用户输入直拼 SQL，见 项目文档 12.2）：任何新写库入口必须先过 `checkNameValid` 校验，不得引入未校验的表名拼接。
4. **颜色/主题**走 `lib/constants/theme_color.dart` 与 `lib/utils/color.dart`，禁止硬编码颜色值；文案中文，不引入 intl。
5. 字符串与 import 用**双引号**；新增业务逻辑配**中文注释**讲清意图，不写废话注释。
6. 错误处理沿用 `try/catch + print + BotToast / EasyLoading` 风格（SDK 层正在迁移为不直接弹 toast，见重构计划 P3）。
7. 只用仓库相对路径；修改文件**保留原有换行符**；diff 尽量小，不顺手重排无关代码。
8. **B 站接口相关改动**（签名/风控/playurl）改前先读 `memories/origin_sdk/`，该层极易因接口漂移而坏，改后必须真机/桌面实测播放。
9. 新沉淀的模块知识按 `.agents/skills/dev_memory` 约定写入 `memories/` 并登记索引。

## 验证基线

- 当前真实基线（未动代码前的原始状态）：`flutter analyze` 有 3 个 error（`test/widget_test.dart` Flutter 模板残留所致，项目文档 12.1）+ 2 个 info；`flutter test` 无法编译。
- 修测试/清 info 属于代码改动，须按硬规则第 0 条先获用户确认。

## 知识源地图（按顺序查）

| 层 | 文件 | 什么时候读 |
| --- | --- | --- |
| 全景事实源 | `项目文档.md` | 接手必读：架构（4~6 章）、模块（7 章）、已知问题编号（12 章） |
| 下钻记忆 | `memories/` | 改某模块前：引用关系图、易踩坑、易腐字段 |
| 角色技能 | `.agents/skills/` | 架构分析（tech-lead-architect）、写码（senior-frontend-engineer）、测试（senior-qa-engineer）、评审（code-reviewer）、沉淀（dev_memory） |
| UI 原型 | `prototype/` | 六套风格稿；**已选定 A · 沉浸极光玻璃 + 玻璃拟态（2026-10-24）**，视觉基线 `style-a-aurora/`，落地方式见 `重构计划.md` P4（UI 动工仍需所有者批准） |
| 重写路线 | `重构计划.md` | **重写计划 v3（2026-10-24 定向：仅保留 origin_sdk/bili，UI/状态/数据层全重写；Riverpod 3 + codegen；含已采纳决策 D1/D6/D7/D8 与阶段 W0~W4）** |
