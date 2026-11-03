import "package:flutter/material.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../data/local_audio_scanner.dart";

/// 扫描完成后的失败文件弹窗（居中；路径完整展示，过长省略）
Future<void> showScanFailuresDialog(
  BuildContext context,
  List<ScanFailure> failures,
) {
  final t = AuroraTokens.of(context);
  final errorColor = Theme.of(context).colorScheme.error;

  return AppDialog.show<void>(
    context,
    title: "有 ${failures.length} 个文件未能读取",
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: failures.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(failures[index].path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: "monospace",
                        fontSize: 11.5,
                        height: 1.35,
                        color: errorColor)),
                const SizedBox(height: 4),
                Text(failures[index].reason,
                    style: TextStyle(fontSize: 11.5, color: t.fgDim)),
              ]);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          "知道了",
          style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}
