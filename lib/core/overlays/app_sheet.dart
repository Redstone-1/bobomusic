import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "../widgets/desktop_content.dart";

/// 底部操作面板的一项（图标 + 文案 + 回调）
/// [selected] 为真时瓦片主题色描边高亮（单选类面板表达当前项，不再用对勾图标）
class AppSheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool selected;

  const AppSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.selected = false,
  });
}

/// 底部操作面板（原型 .sheet：26 圆角面板 + grab 条 + 遮罩渐隐）
/// 列表长按菜单 / 播放页操作面板统一走这里；[child] 用于纯内容面板（播放队列等）
class AppSheet {
  AppSheet._();

  /// 操作项两列瓦片网格（以「歌词设置」_LyricToolTile 为标准逐项对齐）：
  /// tileBg 填充无边框、图标 20、文字 12.5/w600、padding 水平 10 垂直 12、行/列距 10；
  /// 奇数项最后一行通栏。手机弹层与桌面面板共用，全仓唯一瓦片实现。
  static Widget _actionsGrid(
    BuildContext context,
    List<AppSheetAction> actions, {
    required VoidCallback pop,
  }) {
    final t = AuroraTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget tile(AppSheetAction action) {
      final accent = action.danger ? scheme.error : t.primary;
      return InkWell(
        key: ValueKey("sheet_action_${action.label}"),
        onTap: () {
          pop();
          action.onTap();
        },
        borderRadius: BorderRadius.circular(t.radiusMd),
        splashColor: t.surface2,
        highlightColor: t.surface,
          child: Container(
          // 水平留白 10 与行列距同值：长文案不顶瓦片边缘
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(
            color:
                action.selected ? t.primary.withValues(alpha: 0.12) : t.tileBg,
            borderRadius: BorderRadius.circular(t.radiusMd),
          ),
          child: Column(
            children: [
              Icon(action.icon, size: 20, color: accent),
              const SizedBox(height: 6),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: action.danger ? scheme.error : t.fg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              children: [
                Expanded(child: tile(actions[i])),
                if (i + 1 < actions.length) ...[
                  const SizedBox(width: 10),
                  Expanded(child: tile(actions[i + 1])),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static Future<T?> show<T>(
    BuildContext context, {
    List<AppSheetAction> actions = const [],
    Widget? child,
    bool sidePanel = false,
    bool inset = false,
  }) {
    if (DesktopContent.of(context)) {
      final t = AuroraTokens.of(context);
      return showGeneralDialog<T>(
        context: context, barrierDismissible: true, barrierLabel: "关闭面板",
        barrierColor: t.maskBg, transitionDuration: t.motionFast,
        pageBuilder: (dialogContext, animation, secondaryAnimation) => SafeArea(
          child: Align(alignment: sidePanel ? Alignment.centerRight : Alignment.center,
            child: Padding(padding: const EdgeInsets.all(18), child: Material(
              color: t.bg2, borderRadius: BorderRadius.circular(t.radiusLg),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: sidePanel ? 380 : 460, maxHeight: MediaQuery.sizeOf(dialogContext).height - 100),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (child != null) Flexible(child: child),
                  if (actions.isNotEmpty)
                    Flexible(child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: _actionsGrid(dialogContext, actions,
                              pop: () => Navigator.of(dialogContext).pop()),
                        ))),
                ]),
              ),
            )),
          ),
        ),
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AuroraTokens.of(context).maskBg,
      builder: (sheetContext) {
        final t = AuroraTokens.of(sheetContext);
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

        return Container(
          key: const Key("app_sheet_panel"),
          // 规则等选项选择使用带外边距的同款面板，不再让默认菜单贴住屏幕边缘。
          margin: inset
              ? EdgeInsets.fromLTRB(16, 0, 16,
                  (keyboardInset > 0 ? keyboardInset : MediaQuery.viewPaddingOf(sheetContext).bottom) + 12)
              : null,
          clipBehavior: inset ? Clip.antiAlias : Clip.none,
          decoration: BoxDecoration(
            color: t.bg2,
            borderRadius: inset
                ? BorderRadius.circular(t.radiusXl)
                : BorderRadius.vertical(top: Radius.circular(t.radiusXl)),
            border: inset
                ? Border.all(color: t.hairline, width: 1)
                : Border(top: BorderSide(color: t.hairline, width: 1)),
          ),
          child: SafeArea(
            top: false,
            bottom: !inset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // grab 条（原型 44×5）
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: t.hairlineStrong,
                  ),
                ),
                if (child != null) child,
                if (actions.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 2, 22, 24),
                      child: _actionsGrid(
                        sheetContext,
                        actions,
                        pop: () => Navigator.of(sheetContext).pop(),
                      ),
                    ),
                  ),
                if (actions.isEmpty) const SizedBox(height: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}
