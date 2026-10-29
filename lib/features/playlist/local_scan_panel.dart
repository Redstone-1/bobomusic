import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/material.dart";

import "../../core/theme/aurora_tokens.dart";
import "local_scan_controller.dart";

/// 本地扫描的科幻扫描舱（内嵌在列表区域）：
/// 扫描线/网格 + 完整路径文件流 + 计数 + 阶段条 + 取消。
class LocalScanPanel extends StatefulWidget {
  final LocalScanController controller;
  final VoidCallback onCancel;

  const LocalScanPanel({
    super.key,
    required this.controller,
    required this.onCancel,
  });

  @override
  State<LocalScanPanel> createState() => _LocalScanPanelState();
}

class _LocalScanPanelState extends State<LocalScanPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanLine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  final _logScroll = ScrollController();
  String? _lastPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _scanLine.stop();
    } else if (!_scanLine.isAnimating) {
      _scanLine.repeat();
    }
  }

  @override
  void dispose() {
    _scanLine.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  void _scheduleScrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logScroll.hasClients) return;
      _logScroll.animateTo(
        _logScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final latest =
            controller.recentPaths.isEmpty ? null : controller.recentPaths.last;
        if (latest != null && latest != _lastPath) {
          _lastPath = latest;
          _scheduleScrollToEnd();
        }

        return Container(
          decoration: BoxDecoration(
            color: t.bg2.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(t.radiusLg),
            border: Border.all(color: t.hairline, width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.phase == LocalScanPhase.done
                              ? "扫描完成"
                              : "正在扫描本地音乐",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.fg,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${controller.scanned}",
                              style: TextStyle(
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w300,
                                color: t.fg,
                                fontFeatures: [
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: "已发现 · 已入库 ",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.fgMute,
                                      ),
                                    ),
                                    TextSpan(
                                      text: "${controller.indexed}",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text: " · 失败 ",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.fgMute,
                                      ),
                                    ),
                                    TextSpan(
                                      text: "${controller.failed}",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: controller.failed > 0
                                            ? errorColor
                                            : t.fgMute,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.radar, size: 22, color: t.primary),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.radiusMd),
                    border: Border.all(color: t.toastBorder, width: 1),
                  ),
                  padding: const EdgeInsets.all(1),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(t.radiusMd - 1),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: t.scanSurface),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridPainter(t.toastBorder),
                          ),
                        ),
                        Positioned.fill(
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (rect) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                t.fg.withValues(alpha: 0),
                                t.fg,
                                t.fg,
                                t.fg.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.12, 0.88, 1],
                            ).createShader(rect),
                            child: ListView.builder(
                              controller: _logScroll,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              itemExtent: 22,
                              itemCount: controller.recentPaths.length,
                              itemBuilder: (context, index) {
                                final path = controller.recentPaths[index];
                                final current =
                                    index == controller.recentPaths.length - 1;
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: "monospace",
                                      fontSize: 10.5,
                                      height: 1.2,
                                      color: current ? t.primary : t.fgMute,
                                      fontWeight: current
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        if (controller.recentPaths.isEmpty)
                          Center(
                            child: Text(
                              "等待扫描文件…",
                              style: TextStyle(fontSize: 11, color: t.fgMute),
                            ),
                          ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _scanLine,
                                builder: (context, _) => CustomPaint(
                                  painter: _ScanLinePainter(
                                    progress: 0.5 -
                                        0.5 *
                                            math.cos(
                                              2 * math.pi * _scanLine.value,
                                            ),
                                    color: t.primary,
                                    glow: t.glow,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _PhaseBar(controller: controller),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 14, color: t.fgMute),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      "${controller.indexed} 首已入库",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: t.fgMute),
                    ),
                  ),
                  if (controller.canCancel)
                    TextButton(
                      onPressed: widget.onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: t.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        "取消扫描",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (controller.phase == LocalScanPhase.syncing)
                    Text(
                      "正在写入曲库…",
                      style: TextStyle(fontSize: 11, color: t.fgDim),
                    )
                  else if (controller.phase == LocalScanPhase.done)
                    Text(
                      "完成",
                      style: TextStyle(fontSize: 11, color: t.primary),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhaseBar extends StatelessWidget {
  final LocalScanController controller;

  const _PhaseBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final reading = controller.scanned > 0;
    final syncing = controller.phase == LocalScanPhase.syncing ||
        controller.phase == LocalScanPhase.done;

    Widget dot(String label, bool active, bool done) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? t.primary : t.fgMute.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: done
                  ? t.fg
                  : active
                      ? t.fgDim
                      : t.fgMute,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      );
    }

    Widget line(bool active) {
      return Expanded(
        child: Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: active ? t.primary.withValues(alpha: 0.55) : t.hairline,
        ),
      );
    }

    return Row(
      children: [
        dot("遍历", true, true),
        line(reading),
        dot("读取", reading, syncing),
        line(syncing),
        dot("入库", syncing, controller.phase == LocalScanPhase.done),
      ],
    );
  }
}

/// 低透明度网格 + 同心圆，作为扫描舱底图
class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7;
    const step = 28.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 上下往复的扫描光束（渐变拖尾 + 细核心线）
class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color glow;

  const _ScanLinePainter({
    required this.progress,
    required this.color,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = progress * size.height;
    final rect = Rect.fromLTWH(0, y - 18, size.width, 36);
    final beam = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.16),
          color.withValues(alpha: 0.8),
          color.withValues(alpha: 0.16),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.3, 0.5, 0.7, 1],
      ).createShader(rect);
    canvas.drawRect(rect, beam);

    final halo = Paint()
      ..color = glow.withValues(alpha: 0.18)
      ..strokeWidth = 10;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), halo);

    final core = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), core);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
