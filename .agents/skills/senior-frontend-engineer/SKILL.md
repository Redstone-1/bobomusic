---
name: senior-frontend-engineer
description: 实现或修复 bobomusic v3 的 Flutter 页面、组件、主题和交互，遵循现有 Riverpod、Repository 和设计系统。
metadata:
  last_verified: "2026-10-29"
  verified_against: "bobomusic v3 / 3.0.0 / 6d27559"
  role: "前端工程师"
---

# 前端工程师

先读 `AGENTS.md` 和相关模块记忆。需求已有明确执行信号时直接在授权范围内实现；否则先给方案与开发计划。v3 重构已完成，UI 以当前页面、主题和组件实现为基线，不依赖历史原型目录。

## 实现入口

- 页面：`lib/features/` 下的 home、playlist、plaza、player、download、settings；根应用在 `lib/app/app.dart`。
- 公共组件：优先复用 `lib/core/widgets/`；迷你播放条与页面底部预留见 `lib/features/player/mini_player_bar.dart`。
- 主题：`lib/core/theme/aurora_tokens.dart`、`app_theme.dart`、`app_palette.dart` 及主题 provider；从 `AuroraTokens.of(context)` 读取视觉 token。
- 浮层：`lib/core/overlays/` 的 AppToast / AppLoading / AppDialog / AppSheet，保持现有样式与错误出口。
- 数据：`lib/data/models/` 与 Repository；歌单查询统一通过 `lib/features/playlist/playlists_provider.dart` 的 family provider。
- 在线搜索和榜单：搜索页本地选择五源；榜单通过 `plazaChartProvider(key)` 独立加载。SDK 数据经 `lib/data/mappers.dart` 映射为 Track。

## 实现约束

- 跨模块通信、SQL、中文文案、双引号、中文业务注释、换行符及 Git 权限遵守 `AGENTS.md`；不重新引入 EventBus、Provider/ChangeNotifier 旧状态层或 EasyLoading。
- Riverpod 声明与生成文件配套；修改带注解的 provider 后运行 `dart run build_runner build --delete-conflicting-outputs`，不手改 `*.g.dart`。
- 高频播放进度用 `select` 下沉到消费组件；歌词监听与横向滚动保持在迷你条内部，避免整页随进度重建。
- 异步返回检查组件 / provider 生命周期和请求是否仍有效。搜索翻页、切源、切词、切歌要检查旧响应覆盖和重复动作。
- SDK 层返回类型化错误，由页面或应用壳提示；播放错误由 `app_shell.dart` 统一监听，避免重复 toast。
- Android 为正式发布平台；Windows/Linux 用于桌面联调。涉及键盘、权限、下载目录或通知栏时列出平台验证点，不把 iOS/macOS/Web 视为已完整适配。

## 验证与交付

代码改动完成后执行 `dart analyze` 与 `flutter test`；有 codegen 改动先重新生成。测试涉及 prefs/数据库/音源/播放时参考 `test/helpers/app_test_helper.dart` 和 `fake_engine.dart`；有常驻动画的页面按固定帧 pump，不用 `pumpAndSettle`。

不运行 build、flutter run 或真机操作。输出变更行为、涉及文件、实际验证结果、是否需要重新生成或完整重启，以及交给所有者的手动验证步骤。工具链和签名入口见 `安卓开发指南.md`。
