import "package:flutter/material.dart";

import "../../data/models/track.dart";
import "../theme/aurora_tokens.dart";
import "cover_placeholder.dart";
import "eq_bars.dart";
import "origin_tag.dart";

/// 歌曲行（原型 .songrow）
/// [playing] = 当前曲目高亮（§3.4-3：按曲目身份全局判定，由调用方传入）
/// [showOriginTag] 控制音源标签显隐（D11）
/// [coverOverride] 统一封面（歌手歌单等场景整列表共用一张封面），空则用曲目自身封面
/// [likedHeart] 非空时行尾（更多菜单左侧）显示喜欢心形（我喜欢列表快速取消收藏），
/// 点击回调新状态，视觉由调用方状态驱动（不强制刷新列表）
class SongListTile extends StatelessWidget {
  final Track track;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onMorePressed;
  final bool showOriginTag;
  final String? coverOverride;
  final bool? likedHeart;
  final ValueChanged<bool>? onHeartTap;

  const SongListTile({
    super.key,
    required this.track,
    this.playing = false,
    this.onTap,
    this.onMorePressed,
    this.showOriginTag = true,
    this.coverOverride,
    this.likedHeart,
    this.onHeartTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radiusMd),
      splashColor: t.surface2,
      highlightColor: t.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            CoverPlaceholder(
              cover: coverOverride ?? track.effectiveCover,
              text: track.effectiveName,
              size: 48,
              radius: t.radiusSm,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.effectiveName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      // 播放中的曲目标题染主题色（原型 .songrow.playing .t）
                      color: playing ? t.primary : t.fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (showOriginTag) ...[
                        OriginTag(origin: track.origin),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          track.effectiveAuthor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: t.fgDim),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 尾部操作固定顺序：播放波浪 → 喜欢 → 更多（播放中波浪在心形左侧，
            // 所有者 2026-10-27 定）。心形与更多用同规格 32 触控盒（图标 18 居中，
            // 两侧各内缩 7）相邻排布，图标视觉间距恒定 14；波浪后补 7 的间隙，
            // 与右侧首个图标的视觉间距同为 14，保证各组合下间距一致。
            // 尾部整块用不透明手势吸收盲区点击（图标间隙、图标边缘），只消费不透传，
            // 避免想点喜欢/更多时落空触发整行 InkWell 误播歌曲。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (playing) ...[
                    const EqBars(),
                    const SizedBox(width: 7),
                  ],
                  if (likedHeart != null)
                    IconButton(
                      onPressed: onHeartTap == null
                          ? null
                          : () => onHeartTap!(!likedHeart!),
                      icon: Icon(
                        likedHeart! ? Icons.favorite : Icons.favorite_border,
                      ),
                      iconSize: 18,
                      color: likedHeart! ? t.primary : t.fgMute,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  IconButton(
                    onPressed: onMorePressed,
                    icon: const Icon(Icons.more_vert),
                    iconSize: 18,
                    color: t.fgMute,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
