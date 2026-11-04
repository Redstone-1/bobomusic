import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";
import "glass_card.dart";

/// 列表内即时搜索统一使用现有玻璃样式，避免各页面落回 Material 默认下划线。
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final Key? fieldKey;

  const AppSearchField(
      {super.key,
      required this.controller,
      required this.onChanged,
      required this.hintText,
      this.fieldKey});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return GlassCard(
      frosted: true,
      radius: t.radiusMd,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 14, color: t.fg),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(fontSize: 14, color: t.fgMute),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                    icon: Icon(Icons.cancel, size: 18, color: t.fgMute),
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
