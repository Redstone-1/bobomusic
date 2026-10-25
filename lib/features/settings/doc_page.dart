import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:markdown_widget/markdown_widget.dart";

import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/page_header.dart";

/// 帮助 / 声明 / 鸣谢：渲染 assets/markdown 下的静态文档（markdown_widget）
class DocPage extends StatelessWidget {
  final String title;
  final String asset;

  const DocPage({super.key, required this.title, required this.asset});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final dark = t.bg.computeLuminance() < 0.5;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: BackLink(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: PageHeader(title: title),
              ),
              Expanded(
                child: FutureBuilder<String>(
                  future: rootBundle.loadString(asset),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          "文档加载失败",
                          style: TextStyle(fontSize: 13, color: t.fgDim),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: t.primary,
                        ),
                      );
                    }
                    return MarkdownWidget(
                      data: snap.data!,
                      selectable: true,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      config: dark
                          ? MarkdownConfig.darkConfig
                          : MarkdownConfig.defaultConfig,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
