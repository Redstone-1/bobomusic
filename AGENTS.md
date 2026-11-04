# AGENTS.md — 啵啵音乐 AI 开发约定

> 所有 AI agent（主会话 / 子 agent / 排查 / 评审）动手改本仓库前，先读本文。
> 本文是约定入口；当前实现知识见 `memories/`，开发环境见 `安卓开发指南.md`。

## 项目是什么

- 单仓库 Flutter 音乐 App（`com.bobomusic`），v3 已完成重构，当前版本从 `pubspec.yaml` 读取。协作工具链基线 Flutter 3.47.7 / Dart 3.13.5 / JDK 17，Android 配置以当前 Gradle 文件为准。
- **无后端**：在线音源为 Bilibili、酷我、网易云、QQ 音乐、千千；歌词搜索链为网易直连 → LRCLIB → timelessq。用户数据本地保存（sqflite + SharedPreferences）。
- Android 正式发布；Windows x64 已实现桌面界面、系统媒体桥和打包流程，完整运行验收仍在进行；Linux 可用于联调，iOS/macOS/Web 未完成适配。Windows 操作见 `windows/发布与验收.md`。
- 上游基于 [bbmusic](https://github.com/bb-music/flutter-app) 二次开发。`项目文档.md` 保留 master / 2.7.0 历史，不作为 v3 当前架构或缺陷清单。
- UI 参考当前 `lib/core/` 与 `lib/features/` 实现；历史重构计划和原型目录已不再是工作依赖。

## 常用命令

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # 修改带注解的 provider 后
dart analyze
flutter test
```

- 设备运行与发布命令见 `安卓开发指南.md`，由所有者执行。
- 不擅自 `git stage/add/commit/push/revert`；版本操作由所有者完成。

## 目录速览

```text
lib/
├── main.dart           # prefs / 数据库 / 缓存 / 平台播放初始化 → ProviderScope
├── app/                # 根 App、Windows 桌面壳、启动失败页与演示入口
├── core/               # theme / widgets / overlays / permissions / prefs
├── features/           # home / playlist / plaza / player / download / settings
├── data/               # models / repositories / db / 音源实例 / 本地扫描与导入
├── origin_sdk/         # bili / kuwo / netease / qq / qianqian / lyric
└── utils/
test/
└── helpers/            # buildTestApp、五源 Fake、歌词 Fake、FakeEngine
```

## 硬规则（违反即返工）

0. **动工与授权**：
   - 不替用户做需求和方案决策；先给方案设计与开发计划，经允许再动工。用户已给出明确执行方案或执行信号时直接执行授权内容。
   - 改动代码后不执行 build；`flutter run`、真机和桌面交互验证由所有者执行。
   - 不执行 `git add / commit / push / revert`。
   - 技术方案经用户采纳后才能同步文档；未采纳的方案只留在对话里。用户明确要求维护现有文档时，可直接更新已核实事实。
1. **跨模块通信**走 Riverpod provider 依赖图（`ref.watch` / `ref.listen`），禁止 event_bus 与模块间直接 import。
2. **歌单数据读取**统一走 Repository + family provider（by playlistId），禁止 UI 直读库。
3. **SQL 全参数化**：固定 schema 为 tracks / playlists / playlist_items / queue / play_history；不拼接用户输入为表名或 SQL。批量 IN 只生成占位符，值走参数。
4. **UI 与设计一致性**：
   - 颜色/主题走 `lib/core/theme/` 的 token（ThemeExtension 承载），禁止硬编码颜色值；文案中文，不引入 intl。
   - 新增或修改 UI 前，先检索 `lib/core/widgets/`、`lib/core/overlays/` 和现有同类页面，确定已认可的组件与设计基线。同一用途、同一交互场景必须复用同一公共组件；现有实现是页面私有组件时，先提取公共组件再接入新旧页面，不逐页复制样式。
   - 一致性同时包括外框、圆角、背景、字号、间距、图标、触控区域及聚焦、清除、禁用等适用状态；只使用相同主题 token 不等于设计一致。禁止用未封装样式的 Material 默认控件替换已有同类设计。不同用途或平台确需差异时，在共享组件中明确表达必要变体，遵循用户已确认的设计。
   - 列表内即时搜索统一使用 `lib/core/widgets/app_search_field.dart`，本地音乐、我喜欢和全部歌单只调整提示词及过滤逻辑。交付前对照同类页面核查外观与交互，并按改动覆盖必要的明暗、聚焦、清除、窄屏及键盘状态；不能仅凭 analyze/test 通过认定视觉一致，未做设备视觉验收须说明。
   - 编辑表单复用 `lib/core/widgets/app_form_field.dart`；选项入口使用其中的 `AppSelectionField` 配合 `AppSheet`，需要四周留白时使用 `inset` 变体。紧邻文字的复选框复用 `lib/core/widgets/app_checkbox_row.dart`，方框与文字均可切换，尾部操作独立响应。没有播放条时不固定预留播放条高度。
5. 字符串与 import 用双引号；新增业务逻辑配中文注释讲清意图，不写废话注释。
6. 错误处理沿用 try/catch + print；UI 通过 `lib/core/overlays/` 提示，SDK 层错误类型化、不直接弹 toast。播放错误由应用壳统一监听提示。
7. 仓库内文件与文档只用仓库相对路径；修改文件保留原有换行符；diff 尽量小，不顺手重排无关代码。
8. **B 站接口相关改动**（签名/风控/playurl）改前先读 `memories/origin_sdk/`；改后必须由所有者在真机或桌面实测播放。其它在线音源同样区分解析测试与线上可用性。
9. 新沉淀的模块知识按 `.agents/skills/dev-memory/SKILL.md` 写入 `memories/` 并逐层登记索引。

## 验证门槛

- 代码交付门槛：`dart analyze` 零 issue + `flutter test` 全绿；不满足不得交付。
- 静态检查以 `dart analyze` 为准：riverpod_lint 使用 Dart 3.10+ 新式 analyzer 插件，不能以 `flutter analyze` 替代。
- 带注解的 provider 改动要同步 codegen，不手改 `*.g.dart`。
- 文档改动检查事实、索引、本地链接和路径，不固化当前用例数量或检查结果。改码后不执行 build，手动验证交所有者。

## 知识源地图（按需下钻）

| 层 | 入口 | 什么时候读 |
| --- | --- | --- |
| 当前实现 | `lib/`、`test/`、`pubspec.yaml`、Android / Windows 工程配置 | 核实行为、依赖、平台与工具链 |
| 模块记忆 | `memories/README.md` | 改模块前：关系图、状态链、易踩坑与排查入口 |
| 角色技能 | `.agents/skills/` | 架构分析、前端实现、QA、评审、记忆维护 |
| 开发指南 | `安卓开发指南.md`、`windows/发布与验收.md` | 环境搭建、签名、codegen、验证、运行与发布 |
| UI 基线 | `lib/core/theme/`、`lib/core/widgets/`、现有页面 | 主题、组件、交互与布局参考 |
| 旧版历史 | `项目文档.md`、git 历史 | 对照 2.7.0 行为与迁移背景，不套用旧架构硬规则 |

新会话读本文件 → 看 `git status` / `git log` → 从模块索引下钻。测试环境使用可替换全局（appPrefs/appDb、五源 API、lyricService、playbackDepsTestOverride 等）；数据与播放测试先读 `test/helpers/app_test_helper.dart`。
