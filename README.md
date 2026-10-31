<div align="center">

<img src="./assets/readme-logo.png" width="180" alt="啵啵音乐 Logo" />

# 啵啵音乐

**听歌自由 —— 无后端的跨平台本地音乐播放器**

<p>
  <a href="https://github.com/Redstone-1/bobomusic/releases"><img alt="Release" src="https://img.shields.io/badge/Release-v3.0.0-2EC4B6?style=flat-square" /></a>
  <a href="https://docs.flutter.dev/"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.47.7-02569B?style=flat-square&logo=flutter" /></a>
  <a href="#-平台支持"><img alt="Platform" src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop-3FA9CF?style=flat-square" /></a>
  <a href="#"><img alt="Storage" src="https://img.shields.io/badge/Storage-本地存储-738FDE?style=flat-square" /></a>
</p>

聚合五大主流公开音源与本地音乐，
歌单、歌词、下载、播放队列全部数据本地存储，无广告、无账号、无后端。

</div>

## ✨ 功能特色

**音源与播放**

- 🎧 多源聚合搜索：五大主流公开音源一站聚合，搜索页一键切换
- 📻 广场多源榜单：热歌、飙升等官方榜单直接点播
- ▶️ 播放队列：待播放插队、合集批量加入、跨启动恢复
- ⏱️ 定时关闭：计时停止或播完当前再停
- 🕘 播放历史自动记录

**歌单与数据**

- 🎼 自由创建歌单、批量喜欢、本地音乐扫描导入
- 💾 全部数据本地保存（SQLite + SharedPreferences），无账号体系
- 📥 下载离线听：缓存复用边下边播，移动端支持导出到系统文件管理

**歌词与体验**

- 📝 歌词多级智能检索：站内直连 → 开放歌词库 → 备选源，滚动、时间校准、搜索替换
- 🌌 沉浸式极光玻璃界面，深空黑等多主题换色
- 🔍 应用内检查更新

**系统集成**

- 🔔 系统媒体卡：锁屏、控制中心、耳机线控全接入
- 🖥️ 桌面端可用于开发联调

## 📥 下载

[GitHub Releases](https://github.com/Redstone-1/bobomusic/releases)（推荐，CI 自动打包）

## 📱 平台支持

| 平台 | 状态 |
| --- | --- |
| Android | ✅ 正式发布 |
| iOS | 🧪 功能就绪 |
| Desktop | 🛠️ 开发联调 |

## 🛠️ 从源码构建

```bash
git clone https://github.com/Redstone-1/bobomusic.git
cd bobomusic
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run          # 或 flutter build apk
```

工具链要求：Flutter 3.47.7 / Dart 3.13.5 / JDK 17（移动端构建）。
更多环境与签名细节见[安卓开发指南](./安卓开发指南.md)。

## 🧱 技术栈

Flutter · Dart · Riverpod 3（codegen）· just_audio · sqflite · Kotlin / Swift 双端系统媒体桥

架构与协作约定见 [AGENTS.md](./AGENTS.md)。

## ⭐ Star 历史

<a href="https://www.star-history.com/#Redstone-1/bobomusic&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Redstone-1/bobomusic&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Redstone-1/bobomusic&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Redstone-1/bobomusic&type=Date" />
 </picture>
</a>

## 🤝 欢迎贡献

欢迎提交 [Issue](https://github.com/Redstone-1/bobomusic/issues) 与 [PR](https://github.com/Redstone-1/bobomusic/pulls)。

<a href="https://github.com/Redstone-1/bobomusic/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Redstone-1/bobomusic" />
</a>

## 📄 声明

本项目为个人学习研究用途，不存储任何音频文件，全部音源来自各平台公开接口聚合。请支持正版，如有侵权请联系删除。
