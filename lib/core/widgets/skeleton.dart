import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 骨架占位系列（S3：列表区异步加载时的 loading 态）
/// 单一脉冲控制器驱动整组色块透明度，块本身 RepaintBoundary 缓存，成本极低

/// 圆角色块
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double? radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius ?? 8),
          color: t.surface2,
        ),
      ),
    );
  }
}

/// 列表行骨架：封面方块 + 两行文字条（对齐 SongListTile 形状）
/// 文字条撑满可用宽度（标题满宽、副题约 62% 留视觉层次）
class SkeletonListTile extends StatelessWidget {
  final double coverSize;

  const SkeletonListTile({super.key, this.coverSize = 42});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      child: Row(
        children: [
          SkeletonBox(width: coverSize, height: coverSize, radius: t.radiusSm),
          const SizedBox(width: 13),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: w, height: 14),
                    const SizedBox(height: 8),
                    SkeletonBox(width: w * 0.62, height: 11),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区列表加载占位：N 行骨架 + 呼吸脉冲
class SkeletonListView extends StatefulWidget {
  final int rows;

  const SkeletonListView({super.key, this.rows = 3});

  @override
  State<SkeletonListView> createState() => _SkeletonListViewState();
}

class _SkeletonListViewState extends State<SkeletonListView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.55,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulse,
      child: Column(
        children: [
          for (var i = 0; i < widget.rows; i++)
            RepaintBoundary(child: SkeletonListTile()),
        ],
      ),
    );
  }
}
