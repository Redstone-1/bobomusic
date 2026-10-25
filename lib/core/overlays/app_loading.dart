import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 全局加载态（深色玻璃胶囊 + 主题色圈 + 可选文案，居中）
/// 走 showEnhancedWidget 通路（showCustomLoading 的内部包装会裁剪内容，S1.3 实证）；
/// allowClick=false 拦截背后点击，show/dismiss 需成对调用
class AppLoading {
  AppLoading._();

  static CancelFunc? _cancel;

  static void show({String? msg}) {
    // 重复 show 先关旧的，保持单例
    _cancel?.call();
    _cancel = BotToast.showEnhancedWidget(
      allowClick: false,
      crossPage: false,
      // duration null = 不自动关闭，直到 dismiss
      toastBuilder: (_) => Align(
        alignment: Alignment.center,
        child: Builder(
          builder: (context) {
            final t = AuroraTokens.of(context);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: t.toastBg,
                border: Border.all(color: t.toastBorder, width: 1),
              ),
              // 不加 BackdropFilter：底色 alpha 0.92 下模糊不可见；
              // 且动画转圈在 BackdropFilter 图层内曾致内容被裁（S1.3 实证）
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: t.primary,
                    ),
                  ),
                  if (msg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      msg,
                      style: TextStyle(fontSize: 12.5, color: t.toastFg),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 关闭加载态（与 show 成对调用）
  static void dismiss() {
    _cancel?.call();
    _cancel = null;
  }
}
