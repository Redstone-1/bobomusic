import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";

import "../theme/app_palette.dart";

/// 封面：真实数据用网络图（CachedNetworkImage，失败回退渐变+首字占位）
/// mock 数据无 cover 链 → 色相渐变 + 首字 + 高光（原型 grad() / .cv）
class CoverPlaceholder extends StatelessWidget {
  /// 封面 URL（真实数据；空/失败回退占位渐变）
  final String? cover;

  /// 占位首字（真实封面加载中/失败时也不留白）
  final String? text;

  /// 封面色相（mock 用；无值时取标题首字哈希，保证同曲稳定）
  final int? hue;
  final double size;
  final double radius;

  const CoverPlaceholder({
    super.key,
    this.cover,
    this.text,
    this.hue,
    this.size = 48,
    this.radius = 12,
  });

  int get _hue => hue ?? (text?.hashCode ?? 0).abs() % 360;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          // 140° 对角（CSS 角度换算）
          begin: const Alignment(-0.64, -0.77),
          end: const Alignment(0.64, 0.77),
          colors: coverGradientColors(_hue),
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

    if (cover == null || cover!.isEmpty) return fallback;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius)),
      child: CachedNetworkImage(
        imageUrl: cover!,
        fit: BoxFit.cover,
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}
