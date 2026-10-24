import "package:flutter/material.dart";

import "../../data/models/track.dart";
import "../theme/aurora_tokens.dart";

/// 音源标签（D11：歌曲条目与播放页显示 B 站 / 酷我 / 本地）
/// 视觉沿用原型封面角标（黑透玻璃胶囊）
class OriginTag extends StatelessWidget {
  final OriginType origin;

  const OriginTag({super.key, required this.origin});

  static String _label(OriginType o) =>
      switch (o) { OriginType.bili => "B 站", OriginType.kuwo => "酷我", OriginType.local => "本地" };

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: t.coverBadgeBg,
      ),
      child: Text(
        _label(origin),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: t.coverBadgeFg,
        ),
      ),
    );
  }
}
