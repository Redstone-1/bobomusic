import "package:flutter/material.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/desktop_content.dart";

/// 歌单行（原型 .plid：字首封面 + 名称/计数 + 更多）
class PlaylistTile extends StatelessWidget {
  final String name;
  final int count;
  final String? cover;
  final VoidCallback onTap;
  final VoidCallback onMorePressed;

  const PlaylistTile({
    super.key,
    required this.name,
    required this.count,
    this.cover,
    required this.onTap,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    if (DesktopContent.of(context)) {
      return LayoutBuilder(
          builder: (context, constraints) => InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(t.radiusMd),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoverPlaceholder(
                        cover: cover,
                        text: name,
                        size: constraints.maxWidth,
                        radius: t.radiusMd),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: t.fg,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600))),
                      SizedBox(
                          width: 26,
                          height: 26,
                          child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: "歌单操作",
                              iconSize: 16,
                              onPressed: onMorePressed,
                              icon: const Icon(Icons.more_horiz)))
                    ]),
                    Text("$count 首",
                        style: TextStyle(color: t.fgMute, fontSize: 10)),
                  ])));
    }
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
              cover: cover,
              text: name,
              size: 54,
              radius: t.radiusMd,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: t.fg),
                  ),
                  const SizedBox(height: 3),
                  Text("$count 首",
                      style: TextStyle(fontSize: 12.5, color: t.fgDim)),
                ],
              ),
            ),
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
