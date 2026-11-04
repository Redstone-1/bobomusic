import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 复选框紧邻文字，文字和方框都可切换；独立尾部操作不改变勾选状态。
class AppCheckboxRow extends StatelessWidget {
  const AppCheckboxRow(
      {super.key,
      required this.value,
      required this.label,
      required this.onChanged,
      this.trailing});

  final bool value;
  final Widget label;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: MergeSemantics(
                child: InkWell(
          excludeFromSemantics: true,
          borderRadius:
              BorderRadius.circular(AuroraTokens.of(context).radiusMd),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(children: [
              SizedBox(
                  width: 32,
                  height: 40,
                  child: Checkbox(
                    value: value,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: onChanged == null
                        ? null
                        : (checked) => onChanged!(checked ?? false),
                  )),
              const SizedBox(width: 4),
              Expanded(child: label),
            ]),
          ),
        ))),
        if (trailing != null) trailing!,
      ]);
}
