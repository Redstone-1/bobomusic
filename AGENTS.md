# AGENTS.md — 啵啵音乐 AI 开发约定

> 所有 AI agent（主会话 / 子 agent / 排查 / 评审）动手改本仓库前，先读本文。
> 本文是**约定入口**，不是知识全文；知识分层见文末「知识源地图」。

## 项目是什么

- 单仓库 Flutter 音乐 App（`com.bobomusic`），`v2` 分支重写中，重写版版本号 2.0.0（D5）；重写工具链 Flutter 3.47.7 / Dart 3.13.5 / JDK 17（D13）。执行进度一律看 `重构计划.md`，本文不重复记录。
- **无后端**：音源来自 Bilibili 逆向接口（`lib/origin_sdk/bili/`，S2 改造拆 BiliAuth/BiliApi）；歌词链重写中（网易直连 → LRCLIB → 备胎，重构计划 §6）；用户数据全部本地（sqflite + SharedPreferences，S3 落地四表 schema）。
- 正式发布平台 Android；Windows/Linux 桌面可运行；iOS/macOS/Web 未适配。
- 上游基于 [bbmusic](https://github.com/bb-music/flutter-app) 二次开发。

## 常用命令

```bash
flutter pub get
dart analyze             # 改动后必须跑，0 issue（含 riverpod_lint 规则，见「验证门槛」）
flutter test             # 纯 Dart 单测，不依赖设备/网络
flutter run -d windows   # 桌面联调
flutter build apk        # Android 发布（需 android/key.properties 签名）
```

- 环境/签名/真机调试见 `安卓开发指南.md`。
- **禁止在验证前提交**；不擅自 `git stage/commit/push/revert`。

## 目录速览

```
lib/
├── main.dart                  # 入口：ProviderScope → App
├── app/                       # 应用壳：根 Widget、导航骨架（S1.4 填充）
├── core/                      # 设计系统：theme（风格 A token / 主题）、widgets（基础组件，S1.2 填充）
├── features/                  # 业务页面：playlist / plaza / player / settings / gallery（S1.4 填充，gallery 为组件演示页）
├── data/                      # 数据层：models / repositories（S1 mock 形状 = §3 域模型，S3 接真数据）
├── origin_sdk/                # 保留的 B 站逆向成果 bili/（S2 改造）+ origin_types.dart（新数据模型输入）
└── utils/
```

## 硬规则（违反即返工）

0. **动工红线（用户全局规则，优先级最高，全文见 `~/.zcode/AGENTS.md`）**：
   - 不替用户做决定——方案给选项与建议，选择权在用户；
   - 任何需求先出方案设计与开发计划，**经用户允许再动工**（用户给出明确执行方案/执行信号时除外）；
   - 改动代码后**不执行 build**，`flutter run`、真机验证等手动验证一律交由用户；
   - **不执行 `git add` / `git commit`**（`push` / `revert` 同样禁止），版本操作全部由用户手动完成；
   - **所有技术方案必须经过用户同意；必须经过用户采纳后才能同步文档**（含 `重构计划.md`、`memories/`、各 README——未采纳的方案只能出现在对话里，不得落盘成"已定"内容）。
1. **跨模块通信**走 Riverpod provider 依赖图（`ref.watch` / `ref.listen`），禁止 event_bus 与模块间直接 import（重构计划 §4 铁律）。
2. **歌单数据读取**统一走 Repository + family provider（by playlistId），禁止 UI 直读库（重构计划 §3.2/§4）。
3. **SQL 全参数化**（重构计划 §2.2）：新 schema 四表（§3.1）不存在表名拼接；任何新写库入口不得引入未参数化的 SQL 字符串拼接。
4. **颜色/主题**走 `lib/core/theme/` 的 token（S1.2 建立，ThemeExtension 承载），禁止硬编码颜色值；文案中文，不引入 intl。
5. 字符串与 import 用**双引号**；新增业务逻辑配**中文注释**讲清意图，不写废话注释。
6. 错误处理沿用 `try/catch + print + BotToast` 风格（EasyLoading 已随旧版移除；SDK 层错误类型化、不直接弹 toast，S2 落地）。
7. 只用仓库相对路径；修改文件**保留原有换行符**；diff 尽量小，不顺手重排无关代码。
8. **B 站接口相关改动**（签名/风控/playurl）改前先读 `memories/origin_sdk/`，该层极易因接口漂移而坏，改后必须真机/桌面实测播放。
9. 新沉淀的模块知识按 `.agents/skills/dev_memory` 约定写入 `memories/` 并登记索引。

## 验证门槛

> 本节只写稳定规则，**不记录动态状态**——当前多少 error/用例，跑一次命令即是事实源，写进文档必然过时。

- 交付门槛：`dart analyze` 0 issue + `flutter test` 全绿；不满足不得交付（改码后不执行 build，手动验证交所有者，见硬规则 0）。
- 静态检查以 `dart analyze` 为准：riverpod_lint 走 Dart 3.10+ 新式 analyzer 插件，`flutter analyze` 暂不加载新式插件（Flutter 包装器滞后；追平后删本行）。

## 知识源地图（按顺序查）

| 层 | 文件 | 什么时候读 |
| --- | --- | --- |
| 全景事实源 | `项目文档.md` | 接手必读：架构（4~6 章）、模块（7 章）、已知问题编号（12 章） |
| 下钻记忆 | `memories/` | 改某模块前：引用关系图、易踩坑、易腐字段 |
| 角色技能 | `.agents/skills/` | 架构分析（tech-lead-architect）、写码（senior-frontend-engineer）、测试（senior-qa-engineer）、评审（code-reviewer）、沉淀（dev_memory） |
| UI 原型 | `prototype/` | 六套风格稿；**已选定 A · 沉浸极光玻璃 + 玻璃拟态（2026-10-24）**，视觉基线 `style-a-aurora/`，落地方式见 `重构计划.md` §7 与 §9-S1 |
| 重写路线 | `重构计划.md` | 重写决策 D1~D13 与开发计划 S1~S5 全定稿；**执行进度以该文件进度区为准**（本文不记动态状态） |
