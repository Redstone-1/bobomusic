# MEM-2 · 空态 SVG 渲染成一条细线（不可见）

## 现象

空态插画（undraw 提取的 SVG）真机"没加载"：页面空白或只见一条 ~12px 细线；APK 解包确认资源在、`SvgPicture` 组件在、测试"无异常"也通过——肉眼完全看不见。

## 根因链

undraw 镜像包源码是 **JSX** 格式，数值属性写作 `x1={221.48}`、`offset={0}`、根标签 `style={{height:props.height}}`。提取脚本只做了 camelCase→kebab 转换，**没剥花括号**：

- flutter_svg 解析时这些属性全部失效（`x1="{221.48}"` 非法）→ 渐变、定位失效；
- 无 width/height 属性 + viewBox 存在 → 尺寸塌缩成一条线；
- 测试只断言 `findsOneWidget + 无异常`，验证不了"画出来了"。

## 修复（4880cd0）

- 提取脚本补：`={value}` 花括号剥离 → 根标签 JSX style 删除 → camelCase 转换 → 主色替换（#6C63FF→#2EC4B6）。
- 验证方式升级：渲染截图诊断（RepaintBoundary.toImage 出 PNG 人工目检），确认完整渲染后才收工；常驻的冒烟测试 `test/core/empty_asset_test.dart` 锁解析渲染。

## 为何容易复发

"组件存在 + 无异常"断言对**渲染内容损坏**完全无感。凡是从 JSX/HTML 转换来的 SVG 资源，必须目检或像素级断言。

## 关联

[[../plaza/00-模块地图]] · `lib/core/widgets/empty_state.dart`（asset 槽位）
