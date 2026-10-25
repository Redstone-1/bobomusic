import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 全局 Toast（深色玻璃胶囊，明暗同值）
/// 走 BotToast showEnhancedWidget，子组件自带全屏定位；**顶部弹出**（2026-10-25 所有者指定）
class AppToast {
  AppToast._();

  /// 顶部胶囊提示；[duration] 默认 2s
  static void show(BuildContext context, String msg, {Duration? duration}) {
    BotToast.showEnhancedWidget(
      onlyOne: true,
      ignoreContentClick: true,
      crossPage: false,
      duration: duration ?? const Duration(seconds: 2),
      toastBuilder: (_) => Align(
        alignment: Alignment.topCenter,
        child: Builder(
          builder: (context) {
            final t = AuroraTokens.of(context);
            return Container(
              // 顶部安全区之下 12px
              margin: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: t.toastBg,
                border: Border.all(color: t.toastBorder, width: 1),
              ),
              // 不加 BackdropFilter：底色 alpha 0.92 下模糊不可见，白担性能与图层裁剪风险
              child: Text(
                msg,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.toastFg,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
