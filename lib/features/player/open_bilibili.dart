import "package:url_launcher/url_launcher.dart";

import "../../data/models/track.dart";

/// 从曲目 id（aid_bvid[_cid]）提取 B 站 bvid（纯函数，测试锁定）
String? bilibiliBvid(String id) {
  final parts = id.split("_");
  if (parts.length < 2 || parts[1].isEmpty) return null;
  return parts[1];
}

/// 去 B 站看视频：优先 App deep link，失败回退网页（§2.1）
Future<bool> openBilibiliVideo(Track track) async {
  if (track.origin != OriginType.bili) return false;
  final bvid = bilibiliBvid(track.id);
  if (bvid == null) return false;
  try {
    final opened = await launchUrl(
      Uri.parse("bilibili://video/$bvid"),
      mode: LaunchMode.externalApplication,
    );
    if (opened) return true;
  } catch (_) {
    // 未安装 B 站 → 回退网页
  }
  try {
    return await launchUrl(
      Uri.parse("https://www.bilibili.com/video/$bvid"),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
