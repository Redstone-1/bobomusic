import "dart:io";

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 封面统一请求头：网易等封面 CDN 拦截 Dart 默认 UA（实测 403），
/// 必须带浏览器 UA（与 origin_sdk 各源一致）；UI 与媒体中心封面拉取共用
const Map<String, String> coverFetchHeaders = <String, String>{
  "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
};

/// 封面：有 [cover] URL 用网络图（CachedNetworkImage，失败回退占位）；
/// 无封面用主题色纯色占位（带透明度，2026-10-27 所有者定稿，弃渐变方案）
class CoverPlaceholder extends StatelessWidget {
  /// 封面 URL（真实数据；空/失败回退纯色占位）
  final String? cover;

  /// 占位首字（真实封面加载中/失败时也不留白）
  final String? text;
  final double size;
  final double radius;

  const CoverPlaceholder({
    super.key,
    this.cover,
    this.text,
    this.size = 48,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final dark = t.bg.computeLuminance() < 0.5;

    // 纯色占位：主题色 + 透明度（亮色淡雅融合底色，暗色稍实保证可见）
    // 首字用主题色（亮）/高亮白（暗），与底同源不抢内容
    final fallback = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: t.primary.withValues(alpha: dark ? 0.38 : 0.12),
      ),
      child: text == null
          ? null
          : Center(
              child: Text(
                text!.characters.first,
                style: TextStyle(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.92)
                      : t.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.42,
                ),
              ),
            ),
    );

    if (cover == null || cover!.isEmpty) return fallback;

    final localUri = Uri.tryParse(cover!);
    if (localUri?.scheme == "file") {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(File.fromUri(localUri!), width: size, height: size,
            fit: BoxFit.cover, errorBuilder: (context, error, stack) => fallback),
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius)),
      child: CachedNetworkImage(
        imageUrl: cover!,
        httpHeaders: coverFetchHeaders,
        fit: BoxFit.cover,
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}
