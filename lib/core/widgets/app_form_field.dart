import "package:flutter/material.dart";

import "../theme/aurora_tokens.dart";

/// 复用既有歌曲编辑框的圆角填充样式，表单与选项入口共用边框和间距。
InputDecoration _decoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? helper,
  Widget? suffix,
}) {
  final t = AuroraTokens.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
    errorMaxLines: 2,
    labelStyle: TextStyle(fontSize: 13, color: t.fgDim),
    hintStyle: TextStyle(fontSize: 14, color: t.fgMute),
    helperStyle: TextStyle(fontSize: 12, color: t.fgDim),
    filled: true,
    fillColor: t.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.hairline)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.hairline)),
    disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.hairline)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMd),
        borderSide: BorderSide(color: t.primary)),
    suffixIcon: suffix,
  );
}

class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helper,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.keyboardType,
    this.suffix,
  }) : assert(controller == null || initialValue == null);

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;
  final AutovalidateMode autovalidateMode;
  final TextInputType? keyboardType;

  /// 输入框内右侧的操作位（如从设备选图的图标按钮）
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        initialValue: initialValue,
        validator: validator,
        onChanged: onChanged,
        enabled: enabled,
        autofocus: autofocus,
        autovalidateMode: autovalidateMode,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 14.5, color: AuroraTokens.of(context).fg),
        decoration: _decoration(context,
            label: label, hint: hint, helper: helper, suffix: suffix),
      );
}

/// 选择操作使用同一表单外观，由调用方打开应用统一选项面板。
/// [label] 为空时不显示浮标，仅展示当前值。
class AppSelectionField extends StatelessWidget {
  const AppSelectionField({super.key, this.label, required this.value, this.onTap});

  final String? label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Semantics(
        button: true,
        enabled: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radiusMd),
          child: InputDecorator(
            decoration: _decoration(context,
                    label: label,
                    suffix: Icon(Icons.expand_more,
                        color: onTap == null ? t.fgMute : t.fgDim))
                .copyWith(enabled: onTap != null),
            child: Text(value,
                style: TextStyle(
                    fontSize: 14.5, color: onTap == null ? t.fgMute : t.fg)),
          ),
        ));
  }
}
