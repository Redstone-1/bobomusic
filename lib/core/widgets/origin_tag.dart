import "package:flutter/material.dart";

import "../../data/models/track.dart";
import "../theme/aurora_tokens.dart";

/// 音源显示名（D11）：列表标签与通知栏第二行共用
String originLabel(OriginType o) => switch (o) {
      OriginType.bili => "B 站",
      OriginType.kuwo => "酷我",
      OriginType.netease => "网易",
      OriginType.qq => "QQ",
      OriginType.qianqian => "千千",
      OriginType.local => "本地",
    };

/// 音源标签（D11：歌曲条目与播放页显示 B 站 / 酷我 / 本地）
/// 视觉沿用原型封面角标（黑透玻璃胶囊）
class OriginTag extends StatelessWidget {
  final OriginType origin;

  const OriginTag({super.key, required this.origin});

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
        originLabel(origin),
        // height 1.0：CJK 字体默认行盒上下留白不对称，会让小字号在胶囊里视觉偏上
        style: TextStyle(
          fontSize: 10,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: t.coverBadgeFg,
        ),
      ),
    );
  }
}
