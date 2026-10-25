import "package:flutter/material.dart";

import "../../data/models/track.dart";
import "../theme/aurora_tokens.dart";
import "cover_placeholder.dart";
import "eq_bars.dart";
import "origin_tag.dart";

/// 歌曲行（原型 .songrow）
/// [playing] = 当前曲目高亮（§3.4-3：按曲目身份全局判定，由调用方传入）
/// [showOriginTag] 控制音源标签显隐（D11）
class SongListTile extends StatelessWidget {
  final Track track;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onMorePressed;
  final bool showOriginTag;

  const SongListTile({
    super.key,
    required this.track,
    this.playing = false,
    this.onTap,
    this.onMorePressed,
    this.showOriginTag = true,
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
              cover: track.cover,
              hue: track.coverHue,
              text: track.name,
              size: 48,
              radius: t.radiusSm,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
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
                          track.author,
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
            // 播放中显示均衡器，否则显示更多操作
            if (playing)
              const EqBars()
            else
              IconButton(
                onPressed: onMorePressed,
                icon: const Icon(Icons.more_vert),
                iconSize: 18,
                color: t.fgMute,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
