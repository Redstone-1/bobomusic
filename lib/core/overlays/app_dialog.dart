import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "../widgets/app_form_field.dart";

/// 全局弹窗（确认 / 输入 / 自定义）
/// 统一样式：bg2 面板 + 发丝描边 + 18 圆角；遮罩用 token maskBg
/// 约定：传入的 [context] 需能找到 Navigator（真实 App 中必然同时拥有主题 token）
class AppDialog {
  AppDialog._();

  /// 面板容器样式（从弹层自身 context 取 token）
  static Widget _panel(
    BuildContext dialogContext, {
    required Widget child,
  }) {
    final t = AuroraTokens.of(dialogContext);
    return Container(
      key: const Key("app_dialog_panel"),
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: t.bg2,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.hairline, width: 1),
      ),
      child: child,
    );
  }

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    required List<Widget> actions,
    bool barrierDismissible = true,
  }) {
    final t = AuroraTokens.of(context);
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: t.maskBg,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: _panel(
          dialogContext,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(dialogContext, title),
              const SizedBox(height: 14),
              content,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _title(BuildContext context, String title) {
    final t = AuroraTokens.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: t.fg,
      ),
    );
  }

  /// 确认弹窗；返回 true = 确认，false/关闭 = 取消
  /// [danger] 为真时确认钮用错误色（删除类操作）
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    bool danger = false,
    String confirmText = "确定",
    String cancelText = "取消",
  }) {
    final result = showDialog<bool>(
      context: context,
      barrierColor: AuroraTokens.of(context).maskBg,
      builder: (dialogContext) {
        // token 全部从弹层自身 context 取（调用方可能位于主题之外）
        final t = AuroraTokens.of(dialogContext);
        final scheme = Theme.of(dialogContext).colorScheme;

        return Dialog(
          backgroundColor: Colors.transparent,
          child: _panel(
            dialogContext,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(dialogContext, title),
                if (message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: t.fgDim,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(cancelText, style: TextStyle(color: t.fgDim)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(
                        confirmText,
                        style: TextStyle(
                          color: danger ? scheme.error : t.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result.then((v) => v ?? false);
  }

  /// 输入弹窗；确认返回文本，取消/关闭返回 null
  static Future<String?> input(
    BuildContext context, {
    required String title,
    String? hint,
    String? initial,
    String confirmText = "确定",
    String? Function(String?)? validator,
  }) {
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: AuroraTokens.of(context).maskBg,
      builder: (dialogContext) {
        final t = AuroraTokens.of(dialogContext);

        return Dialog(
          backgroundColor: Colors.transparent,
          child: _panel(
            dialogContext,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(dialogContext, title),
                const SizedBox(height: 14),
                Form(
                  key: formKey,
                  child: AppFormField(
                    controller: controller,
                    autofocus: true,
                    validator: validator,
                    hint: hint,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text("取消", style: TextStyle(color: t.fgDim)),
                    ),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? true) {
                          Navigator.of(
                            dialogContext,
                          ).pop(controller.text.trim());
                        }
                      },
                      child: Text(
                        confirmText,
                        style: TextStyle(
                          color: t.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
