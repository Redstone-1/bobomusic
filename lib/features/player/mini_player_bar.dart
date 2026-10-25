import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_progress_bar.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/scale_tap.dart";
import "playback_provider.dart";
import "player_card_page.dart";

/// 推入页（详情/搜索）通用外壳：内容铺满 + 底部迷你条（无播放自隐藏）
class MiniBarPage extends StatelessWidget {
  final Widget child;

  const MiniBarPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 14,
          right: 14,
          // 推入页无底部 Dock，留出下边距避免贴住屏幕底缘
          bottom: 12,
          child: const MiniPlayerBar(),
        ),
      ],
    );
  }
}

/// 封面静止（所有者 2026-10-25 定稿：迷你条封面不旋转）；进度线从封面右侧起
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AuroraTokens.of(context);
    final pb = ref.watch(playbackProvider);
    final track = pb.track;
    if (track == null) return const SizedBox.shrink();
    final progress = pb.duration.inMilliseconds > 0
        ? (pb.position.inMilliseconds / pb.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return ScaleTap(
      key: const Key("mini_player"),
      pressedScale: 0.98,
      onTap: () => PlayerCardPage.open(context, ref, track),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -22,
            ),
          ],
        ),
        // 玻璃本体：surface 只有 5.5% 透明度，必须配背景模糊才可读（原型 backdrop-filter）
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 62,
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: t.surface,
                border: Border.all(color: t.hairline, width: 1),
              ),
              child: Row(
                // 封面与「文字+进度线」块左右布局、等高居中（Row 默认交叉轴居中）
                children: [
                  CoverPlaceholder(
                    cover: track.cover,
                    text: track.name,
                    size: 42,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.fg,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          track.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: t.fgDim),
                        ),
                        const SizedBox(height: 4),
                        // 进度线属于文字块：天然与歌名左对齐，无坐标换算
                        AuroraProgressBar(
                          value: progress,
                          height: 2,
                          showThumb: false,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    key: const Key("mini_play"),
                    onTap: () =>
                        ref.read(playbackProvider.notifier).toggle(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        pb.playing ? Icons.pause : Icons.play_arrow,
                        size: 26,
                        color: t.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
