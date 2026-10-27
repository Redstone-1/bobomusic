import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 空态自绘插画（所有者 2026-10-27 定稿：弃 emoji 与圆底线性 icon，改主题色插画）
/// 与 EmptyState 的 illustration 槽位配合；颜色全部走 AuroraTokens

/// 「最近播放」空态：黑胶唱片 + 时钟指针（最近听过的隐喻）
class RecentEmptyIllustration extends StatelessWidget {
  const RecentEmptyIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return CustomPaint(
      size: const Size(96, 96),
      painter: _RecentEmptyPainter(
        disc: t.bg2,
        groove: t.hairline,
        label: t.primary,
        hand: t.fg,
      ),
    );
  }
}

class _RecentEmptyPainter extends CustomPainter {
  final Color disc;
  final Color groove;
  final Color label;
  final Color hand;

  const _RecentEmptyPainter({
    required this.disc,
    required this.groove,
    required this.label,
    required this.hand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 唱片盘体 + 同心纹
    canvas.drawCircle(center, 40, Paint()..color = disc);
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = groove;
    canvas.drawCircle(center, 40, groovePaint);
    canvas.drawCircle(center, 33, groovePaint);
    canvas.drawCircle(center, 26, groovePaint);
    // 唱片标签即表盘
    canvas.drawCircle(center, 15, Paint()..color = label);
    // 指针（10:10 经典表针构图）：分针长、时针短，圆头笔触
    final handPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = hand;
    canvas.drawLine(
      center,
      center + const Offset(-11, -19),
      handPaint..strokeWidth = 2.5,
    );
    canvas.drawLine(center, center + const Offset(13, -8), handPaint);
    canvas.drawCircle(center, 2.5, Paint()..color = hand);
  }

  @override
  bool shouldRepaint(covariant _RecentEmptyPainter oldDelegate) =>
      oldDelegate.disc != disc ||
      oldDelegate.groove != groove ||
      oldDelegate.label != label ||
      oldDelegate.hand != hand;
}

/// 「下载」空态：敞开的空箱子 + 悬浮音符（没装下任何东西的隐喻）
class DownloadEmptyIllustration extends StatelessWidget {
  const DownloadEmptyIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return CustomPaint(
      size: const Size(96, 96),
      painter: _DownloadEmptyPainter(
        box: t.bg2,
        edge: t.hairline,
        accent: t.primary,
        note: t.fgDim,
      ),
    );
  }
}

class _DownloadEmptyPainter extends CustomPainter {
  final Color box;
  final Color edge;
  final Color accent;
  final Color note;

  const _DownloadEmptyPainter({
    required this.box,
    required this.edge,
    required this.accent,
    required this.note,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = edge;
    // 箱体
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 46, 56, 34),
      const Radius.circular(6),
    );
    canvas.drawRRect(body, Paint()..color = box);
    canvas.drawRRect(body, edgePaint);
    // 敞开的两片盖板（左右外翻的平行四边形）
    final flap = Path()
      ..moveTo(20, 46)
      ..lineTo(4, 34)
      ..lineTo(26, 24)
      ..lineTo(42, 46)
      ..close();
    canvas.drawPath(flap, Paint()..color = box);
    canvas.drawPath(flap, edgePaint);
    final flap2 = Path()
      ..moveTo(72, 46)
      ..lineTo(88, 34)
      ..lineTo(66, 24)
      ..lineTo(50, 46)
      ..close();
    canvas.drawPath(flap2, Paint()..color = box);
    canvas.drawPath(flap2, edgePaint);
    // 箱口主题色描边：视线焦点落在"空"的开口
    canvas.drawLine(
      const Offset(19, 46),
      const Offset(73, 46),
      edgePaint..color = accent..strokeWidth = 2,
    );
    // 悬浮的八分音符（箱子是空的，音符还没装进去）
    final notePaint = Paint()..color = note;
    canvas.drawCircle(const Offset(62, 12), 5, notePaint);
    final stem = Paint()
      ..color = note
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(66.5, 11), const Offset(66.5, -2 + 12), stem);
    // 符尾小弧
    final flag = Path()
      ..moveTo(66.5, 10)
      ..quadraticBezierTo(74, 12, 73, 19);
    canvas.drawPath(
      flag,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = note,
    );
  }

  @override
  bool shouldRepaint(covariant _DownloadEmptyPainter oldDelegate) =>
      oldDelegate.box != box ||
      oldDelegate.edge != edge ||
      oldDelegate.accent != accent ||
      oldDelegate.note != note;
}
