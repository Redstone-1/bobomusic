import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "glass_card.dart";

/// 列表内即时搜索统一使用现有玻璃样式，避免各页面落回 Material 默认下划线。
/// [dense] 桌面顶栏紧凑变体（字号/图标略小、玻璃语言一致）；
/// [onSubmitted]/[textInputAction]/[focusNode]/[autofocus] 支撑回车发起类
/// 页面（广场搜索）统一接入本组件
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final Key? fieldKey;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool dense;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.fieldKey,
    this.onSubmitted,
    this.textInputAction,
    this.focusNode,
    this.autofocus = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return GlassCard(
      frosted: true,
      radius: t.radiusMd,
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
      child: Row(
        children: [
          Icon(Icons.search, size: dense ? 18 : 20, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              style: TextStyle(fontSize: dense ? 12.5 : 14, color: t.fg),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  fontSize: dense ? 12.5 : 14,
                  color: t.fgMute,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(vertical: dense ? 10 : 14),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: "清除搜索",
                    visualDensity: VisualDensity.compact,
                    icon:
                        Icon(Icons.cancel, size: dense ? 16 : 18, color: t.fgMute),
                    onPressed: () {
                      controller.clear();
                      onChanged("");
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
