<a href="https://github.com/Redstone-1/bobomusic">
  <img src="./assets/readme-image.png" alt="bobomusic" />
</a>

<div align="center">
  <br/>
  <h1>啵啵音乐</h1>
  <br/>
  <a>
    <img
      alt="Android"
      src="https://img.shields.io/badge/Android-blue?style=flat-square&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAXdJREFUSEvt1b1LllEYx/GPTWItgW4OJm29OKhLYFMODqGDL+TS5qhCov4FEmgUlINrNCSIOjQIDw66uZQNlU4uLr0QLoLgoPeRc8Ppwcf7eRCHwAMHbji/6/pe1++ci7vOFa+6K87vGlDocLlFj7CEd5gpjP5X8AKTGMBmflQOGMJHHKMNP6qEtGaJv6Eez/G+EuAGttCBdTypErCKXuzgYSzwLPS8V/QYGzFxH36iG3fQHGP+YDcW0YC1qO9JvisCwsEiBnFSoYi0sVzzCU/LOz6vg/vxHu5VaU8u+45hfE3jygHBihXcrDF5Lj9Ef2pTCuiMzyu8hMusAOnKLv1Lesm38RktMfPfOAfP0F5A28YHTGfz0xi1+3iAg7yDl5hKEk3gVSYYx+sCQBiuWYzhTaJ9i9EACNQ93EoOlzGPhay6uwWAEDsSd5jifB0FRwIgjPjcZUy/IHY8AEo1TGytdZQC4FdmR1OtkVXqf1//cAqd+v8tOgXyozpDh5nrrgAAAABJRU5ErkJggg=="
    />
  </a>
  <a>
    <img
      alt="Massive song"
      src="https://img.shields.io/badge/Massive Songs-green?style=flat-square"
    />
  </a>
  <a>
    <img
      alt="Free Download"
      src="https://img.shields.io/badge/Free Download-orange?style=flat-square"
    />
  </a>
  <a>
    <img
      alt="Custom Theme"
      src="https://img.shields.io/badge/Custom Theme-deeppink?style=flat-square"
    />
  </a>
  <a>
    <img
      alt="Local Music Import"
      src="https://img.shields.io/badge/Local Music Import-aquamarine?style=flat-square"
    />
  </a>
  <a>
    <img
      alt="No Ad"
      src="https://img.shields.io/badge/No Ad-red?style=flat-square"
    />
  </a>
</div>

<br/>

> **v2 重写进行中**：`v2` 分支正在重写 UI / 状态管理 / 数据层 / 播放内核（2.0.0 未发布，进度见 [`重构计划.md`](./重构计划.md)）；master 分支的 2.7.0 仍是当前发行版，以下内容对应旧版。

<br/>

# 预览

<img src="./screenshot/preview-1.jpg" alt="bobomusic" />
<img src="./screenshot/preview-2.jpg" alt="bobomusic" />
<img src="./screenshot/preview-3.jpg" alt="bobomusic" />
<img src="./screenshot/preview-4.jpg" alt="bobomusic" />
<img src="./screenshot/preview-5.jpg" alt="bobomusic" />

<br/>

# 下载

## Android 

[Github Release](https://github.com/Redstone-1/bobomusic/releases) | [百度网盘](https://pan.baidu.com/share/init?surl=S0mF6PhN4aXM4VVFPc7PAQ) 提取码：6w7y

# 功能特色

- 🎉 免费
- 📱 支持本地音乐导入
- 🎸 支持歌词
- 🧩 支持自由创建歌单
- 📝 支持待播放列表
- 🎨 支持主题更换
- 🛜 海量网络歌源
- 🔒 数据本地存储
- 💎 界面简洁无广

# 核心依赖版本

- JDK 17

- Flutter 3.27.x

# 开发指南

[安卓开发指南](./安卓开发指南.md)


# 历史星标

<a href="https://www.star-history.com/#Redstone-1/bobomusic&Date">

 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Redstone-1/bobomusic&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Redstone-1/bobomusic&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Redstone-1/bobomusic&type=Date" />
 </picture>
</a>

# 常见问题

- 为什么图片左上角有一小块类似马赛克区域？
  > 在例如 iqoo13 等机型上可见，可以尝试升级系统解决，原因尚不明确

- 为什么重新安装应用后扫描的本地歌曲信息不是之前我编辑后的？
  > 建议安装新版本时不要卸载旧版本

- 为什么有些本地歌曲没有时长信息？
  > 从 bilibili 下载的歌曲没有时长信息，你可以编辑信息进行更正

- 为什么搜索出来的合集不能自动播放下一曲？
  > 因为没有后端，不知道下一曲是哪首，虽然可以临时建个表，但是比较多余，我们有待播放列表，所以你可以把想听的音频添加到待播放列表

# 鸣谢

## [阿炸克斯](https://juejin.cn/user/870468938379272)

本项目播放器、互联网搜索部分基于 [bbmusic](https://github.com/bb-music/flutter-app) 二次开发

## [张风捷特烈](https://juejin.cn/user/149189281194766)

tab 指示器的修改部分使用了 [FlutterUnit](https://github.com/toly1994328/FlutterUnit) 中的代码

# 欢迎贡献

如果你对本项目功能的改进性有建议或者对本项目技术感兴趣，欢迎 PR

<a href="https://github.com/Redstone-1/bobomusic/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Redstone-1/bobomusic" />
</a>
