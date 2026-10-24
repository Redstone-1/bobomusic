import "package:flutter/material.dart";

import "../theme/app_palette.dart";

/// 占位封面：无图时按色相生成 140° 对角渐变 + 首字 + 高光（原型 grad() / .cv）
/// S1 mock 阶段的封面实现；S1.4 页面接真数据时再扩展网络图片态
class CoverPlaceholder extends StatelessWidget {
  /// 封面色相（mock 用；无值时取标题首字哈希，保证同曲稳定）
  final int? hue;
  final String? text;
  final double size;
  final double radius;

  const CoverPlaceholder({
    super.key,
    this.hue,
    this.text,
    this.size = 48,
    this.radius = 12,
  });

  int get _hue => hue ?? (text?.hashCode ?? 0).abs() % 360;

  @override
  Widget build(BuildContext context) {
    final colors = coverGradientColors(_hue);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          // 140° 对角（CSS 角度换算）
          begin: const Alignment(-0.64, -0.77),
          end: const Alignment(0.64, 0.77),
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          // 高光层（原型 .cv::after：白 35% → 透明 55%）
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.6, -0.8),
                end: const Alignment(0.6, 0.8),
                colors: [
                  Colors.white.withValues(alpha: 0.32),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0, 0.55],
              ),
            ),
          ),
          if (text != null)
            Center(
              child: Text(
                text!.characters.first,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.42,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
