# MEM-7 · Windows 工具链与安装权限

> 核对：2026-11-03，源码基线 `073cd0a`。编译错误、安装拒访来自所有者日志/截图；兼容处理后本机 Release 已编译并生成过安装包。最新管理员提权配置按所有者要求未重新生成安装包，UAC 和原用户自动启动仍待新包验收。

## 现象与已核实根因

| 现象 | 根因与边界 |
| --- | --- |
| `Unable to find suitable Visual Studio toolchain` | Flutter doctor 未识别完整 Visual Studio C++ 桌面工具链；仅下载安装器或 IDE 不代表已装工作负载 |
| permission_handler_windows 编译报 STL1011 / `experimental/coroutine` | 插件虽启用 C++20，仍附加旧 `/await`，新版 MSVC 选择已弃用的实验协程头并报错 |
| Inno Setup 找不到简体中文语言文件 | 原脚本假设编译器 Languages 目录自带 ChineseSimplified.isl，实际本机分发没有该文件 |
| 安装到受保护自定义目录报“错误 5：拒绝访问” | 原脚本 `PrivilegesRequired=lowest` 不提权；该次目标父目录 ACL 仅管理员/System 可写，普通用户只读。不能仅凭错误 5 就推断所有拒访原因相同 |

`media_kit_libs_windows_audio` 的 CMP0175 提示在该次日志为 CMake 开发警告，实际终止构建的是 MSVC 错误；不要只屏蔽警告后声称修好编译。

## 当前处理与文件关系

- Visual Studio Installer 选择“使用 C++ 的桌面开发”，保留 x64/x86 MSVC、C++ CMake 工具与 Windows SDK，完成后用 `flutter doctor -v` 检查。
- `windows/CMakeLists.txt` 在插件载入后仅对 `permission_handler_windows_plugin` 移除 `/await`，使用其现有 C++20；不修改生成的 symlink 目录，不全局屏蔽 STL 弃用错误。runner 的 SMTC C++20 配置在 `windows/runner/CMakeLists.txt`。
- `windows/installer.iss` 改用仓库内 `windows/installer/ChineseSimplified.isl`；来源与版本说明在 [资源说明](../../windows/installer/README.md)。本地和 GitHub Actions 共用同一脚本。
- 安装器现配置 `PrivilegesRequired=admin`，默认 `{autopf}/Bobomusic`，保留固定 AppId；用户同意 UAC 后安装。`runasoriginaluser` 用于安装完成后自动启动，应用本身不要求管理员权限。
- 仓库配置改变不会修改旧安装 EXE。`runasoriginaluser` 也不能把所有手动“以管理员身份运行”的启动方式自动还原成普通用户；按正常方式启动安装器验收 UAC 和应用身份。
- 不修改目标目录 ACL 来绕过权限，也不把普通播放进程改为管理员进程。安装目录与用户数据目录分离，后者仍由 path_provider/SharedPreferences 按运行用户决定。

## 回归与排查

工具链问题先查完整 doctor 和首条实际编译错误；拒访先核对安装包版本、UAC 是否出现、目标目录权限及错误路径。新包需验收 UAC 同意/取消、标准账户凭据、受保护路径写入、完成后的原用户启动和升级数据保留。

相关结构见 [桌面地图](../desktop/00-模块地图.md)，操作与待验收项见 [Windows 发布与验收](../../windows/发布与验收.md)。应用页面卡顿尚无确定根因，不从编译器安装、Debug 模式或内存占用直接推导性能结论。
