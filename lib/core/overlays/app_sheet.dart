import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

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
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AuroraTokens.of(context).maskBg,
      builder: (sheetContext) {
        final t = AuroraTokens.of(sheetContext);
        final scheme = Theme.of(sheetContext).colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: t.bg2,
            borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusXl)),
            border: Border(top: BorderSide(color: t.hairline, width: 1)),
          ),
          child: SafeArea(
            top: false,
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
                          Text(
                            action.label,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: action.danger ? scheme.error : t.fg,
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
