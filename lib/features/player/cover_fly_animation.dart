import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_toast.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../data/models/track.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../playlist/playlists_provider.dart" show queueEntriesProvider;
import "playback_provider.dart";

/// 播放条封面锚点（普通 Key，允许同树多实例：手机壳层与推入页各有迷你条）
const Key playerCoverAnchor = Key("player_cover_anchor");

/// 点列表封面 = 加入待播放队列（飞入动画即成功反馈，不再弹 toast）；
/// 还没开始过播放（无播放条）时直接开播，播放条浮现后照播动画。
/// 播放失败仍由应用壳统一监听提示（对齐 PlayerCardPage.start）。
Future<void> addTrackToQueueWithFly(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  required Rect from,
}) async {
  final hasSession = ref.read(playbackProvider).track != null;
  if (hasSession) {
    try {
      // 队列表有外键约束，先确保曲目入库（「下一首播放」同链路）
      await TrackRepository().upsert(track);
      await QueueRepository().append(track.id);
      ref.invalidate(queueEntriesProvider);
    } catch (error) {
      print("加入待播放队列失败：$error");
      if (context.mounted) AppToast.show(context, "加入失败，请重试");
      return;
    }
  } else {
    // 冷启动首播：只开播不弹卡，播放状态由迷你条承接
    TrackRepository().upsert(track);
    await ref.read(playbackProvider.notifier).play(track);
  }
  if (context.mounted) _flyCover(context, track, from: from);
}

/// 遍历根 Overlay 找锚点实例：visitChildren 自底向上（overlay 条目从底到顶），
/// 后访问者覆盖前者 → 结果即最上层可见播放条（推入页优先于壳层被遮实例）
Rect? findPlayerCoverRect(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  Rect? found;
  void visit(Element element) {
    if (element.widget.key == playerCoverAnchor) {
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        found = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    element.visitChildren(visit);
  }

  // OverlayState.context 就是 Element，向下遍历整个路由子树
  (overlay.context as Element).visitChildren(visit);
  return found;
}

/// 找播放条封面 rect；无播放条场景刚开播，封面要等下一帧布局完成，
/// 最多推 3 帧（一直取不到就放弃动画，如开播被引擎拒绝）
void _flyCover(BuildContext context, Track track, {required Rect from}) {
  void attempt(int remaining) {
    if (!context.mounted) return;
    final to = findPlayerCoverRect(context);
    if (to != null) {
      _insertFlyEntry(context, track, from: from, to: to);
    } else if (remaining > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt(remaining - 1));
    }
  }

  attempt(3);
}

void _insertFlyEntry(
  BuildContext context,
  Track track, {
  required Rect from,
  required Rect to,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlyCover(
      track: track,
      from: from,
      to: to,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

/// 封面副本：沿二次贝塞尔弧线（中点上抬）飞向播放条封面，
/// 同步缩放到目标尺寸，尾段渐隐收尾
class _FlyCover extends StatefulWidget {
  final Track track;
  final Rect from;
  final Rect to;
  final VoidCallback onDone;

  const _FlyCover({
    required this.track,
    required this.from,
    required this.to,
    required this.onDone,
  });

  @override
  State<_FlyCover> createState() => _FlyCoverState();
}

class _FlyCoverState extends State<_FlyCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 所有者 2026-11-07 定：1.05s，弧线看得清
    duration: const Duration(milliseconds: 1050),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final eased = Curves.easeInOut.transform(t);
        // 二次贝塞尔：起终点中点上抬约 110px，形成「抛起再落入播放条」的弧线
        final start = widget.from.center;
        final end = widget.to.center;
        final control = Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2 - 110,
        );
        final pos = _quadBezier(start, control, end, eased);
        final size = Size.lerp(widget.from.size, widget.to.size, eased)!;
        // 尾段 25% 渐隐，落点即消失
        final opacity =
            t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0);
        return Positioned(
          left: pos.dx - size.width / 2,
          top: pos.dy - size.height / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: CoverPlaceholder(
                cover: widget.track.effectiveCover,
                text: widget.track.effectiveName,
                size: size.width,
                radius: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}

Offset _quadBezier(Offset a, Offset c, Offset b, double t) {
  final u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
    u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy,
  );
}
