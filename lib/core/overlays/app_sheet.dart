import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "../widgets/desktop_content.dart";

/// 底部操作面板的一项（图标 + 文案 + 回调）
class AppSheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const AppSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
}

/// 底部操作面板（原型 .sheet：26 圆角面板 + grab 条 + 遮罩渐隐）
/// 列表长按菜单 / 播放页操作面板统一走这里；[child] 用于纯内容面板（播放队列等）
class AppSheet {
  AppSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
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
                  if (title != null) Padding(padding: const EdgeInsets.fromLTRB(22, 16, 8, 6), child: Row(children: [Expanded(child: Text(title, maxLines: 2, style: TextStyle(color: t.fg, fontSize: 18, fontWeight: FontWeight.w700))), IconButton(tooltip: "关闭", onPressed: () => Navigator.of(dialogContext).pop(), icon: const Icon(Icons.close))])),
                  if (child != null) Flexible(child: child),
                  if (actions.isNotEmpty) Flexible(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final action in actions) ListTile(leading: Icon(action.icon, color: action.danger ? Theme.of(context).colorScheme.error : t.primary, size: 20), title: Text(action.label, style: TextStyle(color: t.fg, fontSize: 13)), onTap: () { Navigator.of(dialogContext).pop(); action.onTap(); }),
                  ]))),
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
        final scheme = Theme.of(sheetContext).colorScheme;
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
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: t.fg,
                        ),
                      ),
                    ),
                  ),
                if (child != null) child,
                for (final action in actions)
                  InkWell(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      action.onTap();
                    },
                    borderRadius: BorderRadius.circular(t.radiusMd),
                    splashColor: t.surface2,
                    highlightColor: t.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: t.surface2,
                            ),
                            child: Icon(
                              action.icon,
                              size: 18,
                              // 危险操作染错误色，常规操作染主题色（原型 setrow .ic）
                              color: action.danger ? scheme.error : t.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Expanded + 省略：长文案（如「标题 · 歌手」）不得撑爆面板
                          Expanded(
                            child: Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: action.danger ? scheme.error : t.fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}
