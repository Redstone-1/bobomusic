import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// 帮助文档回归：新版文字说明、覆盖核心功能、不再引用旧版截图
void main() {
  test("help_doc 是新版文字版，且旧截图资源已移除", () {
    final doc = File("assets/markdown/help_doc.md").readAsStringSync();

    // 纯文字：不引用旧截图/图片
    expect(doc.contains("assets/images"), isFalse);
    expect(doc.contains("!["), isFalse);

    // 新版核心功能均有说明
    for (final keyword in [
      "歌单",
      "播放队列",
      "B 站",
      "酷我",
      "音源",
      "歌词",
      "校准",
      "下载",
      "文件导入",
      "定时关闭",
      "检查更新",
      "清理音频缓存",
    ]) {
      expect(doc, contains(keyword), reason: "帮助文档应覆盖：$keyword");
    }

    // 旧版术语/项目内部信息不再出现
    for (final forbidden in [
      "待播放列表",
      "1000 首",
      "长按歌单名",
      "重写版",
      "Web",
      "未上架",
      "公开接口",
      "风控",
      "GitHub",
      "开发用",
      "服务器",
      "UGC",
      "第三方",
      "直链",
    ]) {
      expect(doc.contains(forbidden), isFalse, reason: "帮助文档不应出现：$forbidden");
    }

    // 旧版帮助截图目录整体删除
    expect(Directory("assets/images").existsSync(), isFalse);
  });
}
