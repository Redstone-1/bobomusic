import "package:flutter/material.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/back_link.dart";
import "../../core/widgets/glass_card.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/scale_tap.dart";

/// 声明与鸣谢：独立信息页（风格 A 玻璃卡片分节），不再使用通用 Markdown
class DeclarationPage extends StatelessWidget {
  const DeclarationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _InfoScaffold(
      title: "声明与限制",
      subtitle: "使用前请了解以下事项",
      children: [
        _IntroCard(
          icon: Icons.verified_user_outlined,
          title: "请合理使用",
          body: "啵啵音乐是一款免费的音乐播放工具，仅供交流学习使用。"
              "请遵守当地法律法规，尊重音乐创作者与版权方的权益。",
        ),
        SizedBox(height: 14),
        _InfoSection(
          icon: Icons.person_outline,
          title: "使用范围",
          body: "请勿将本 App 用于商业用途，也不要通过出售、出租、传播等方式获取收益。",
        ),
        SizedBox(height: 12),
        _InfoSection(
          icon: Icons.lock_outline,
          title: "数据与隐私",
          body: "无需登录。歌单、喜欢、歌词、播放队列和下载记录只保存在本机；"
              "扫描本地音乐、导入文件和下载时才会申请必要的媒体 / 存储权限，不收集你的个人信息。",
        ),
        SizedBox(height: 12),
        _InfoSection(
          icon: Icons.copyright_outlined,
          title: "内容版权",
          body: "在线音乐来自 B 站、酷我、网易云、QQ 音乐、千千等音源，"
              "歌曲版权归原平台及版权方所有。"
              "请支持正版，勿修改、复制、传播或售卖在线内容。",
        ),
        SizedBox(height: 12),
        _InfoSection(
          icon: Icons.download_outlined,
          title: "下载内容",
          body: "下载的歌曲仅限个人学习使用，请勿分享或用于商业用途；"
              "体验后请删除下载文件，并遵守相关平台的使用规则。",
        ),
        SizedBox(height: 12),
        _InfoSection(
          icon: Icons.cloud_off_outlined,
          title: "内容可用性",
          body: "在线内容可能因平台调整、网络或设备原因暂时无法播放。"
              "遇到问题可以更换音源、更换关键词或稍后重试。",
        ),
        SizedBox(height: 20),
        _FootNote("请合法、合规、合理地使用啵啵音乐。"),
      ],
    );
  }
}

class ThanksPage extends StatelessWidget {
  const ThanksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _InfoScaffold(
      title: "鸣谢",
      subtitle: "感谢这些项目与作者",
      children: [
        _IntroCard(
          icon: Icons.favorite_border,
          title: "站在开源社区的肩膀上",
          body: "啵啵音乐离不开开源项目与贡献者的帮助。感谢每一位让音乐播放变得更简单的人。",
        ),
        SizedBox(height: 6),
        SectionHeader(title: "特别感谢"),
        _LinkCard(
          icon: Icons.queue_music_outlined,
          title: "bbmusic",
          subtitle: "阿炸克斯 / lvyueyang · 播放器与互联网搜索基础",
          url: "https://github.com/bb-music/flutter-app",
        ),
        SizedBox(height: 12),
        _LinkCard(
          icon: Icons.auto_awesome_mosaic_outlined,
          title: "FlutterUnit",
          subtitle: "张风捷特烈 · 早期 Tab 指示器参考",
          url: "https://github.com/toly1994328/FlutterUnit",
        ),
        SizedBox(height: 6),
        SectionHeader(title: "开源组件"),
        _LinkCard(
          icon: Icons.flutter_dash,
          title: "Flutter",
          subtitle: "跨平台 UI 框架",
          url: "https://flutter.dev",
        ),
        SizedBox(height: 12),
        _LinkCard(
          icon: Icons.graphic_eq,
          title: "just_audio",
          subtitle: "音频播放引擎",
          url: "https://github.com/ryanheise/just_audio",
        ),
        SizedBox(height: 12),
        _LinkCard(
          icon: Icons.account_tree_outlined,
          title: "Riverpod",
          subtitle: "状态管理与依赖注入",
          url: "https://riverpod.dev",
        ),
        SizedBox(height: 12),
        _LinkCard(
          icon: Icons.article_outlined,
          title: "markdown_widget",
          subtitle: "帮助文档的 Markdown 渲染",
          url: "https://github.com/asjqkkkk/markdown_widget",
        ),
        SizedBox(height: 20),
        _FootNote("也谢谢每一位使用啵啵音乐的你。"),
      ],
    );
  }
}

/// 统一信息页外壳：极光背景 + 返回 + 大标题 + 可滚动卡片
class _InfoScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _InfoScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: BackLink(),
              ),
              PageHeader(title: title, subtitle: subtitle),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _IntroCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.primary.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 23, color: t.primary),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.65,
                    color: t.fgDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBox(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: t.fgDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ScaleTap(
        onTap: () => _openUrl(context, url),
        pressedScale: 0.98,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _IconBox(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: t.fg,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: t.fgDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, size: 16, color: t.fgMute),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;

  const _IconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: t.surface2,
      ),
      child: Icon(icon, size: 19, color: t.primary),
    );
  }
}

class _FootNote extends StatelessWidget {
  final String text;

  const _FootNote(this.text);

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, color: t.fgMute),
      ),
    );
  }
}

Future<void> _openUrl(BuildContext context, String url) async {
  try {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      AppToast.show(context, "无法打开链接");
    }
  } catch (_) {
    if (context.mounted) AppToast.show(context, "无法打开链接");
  }
}
