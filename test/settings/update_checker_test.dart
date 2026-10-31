import "package:bobomusic/features/settings/settings_info.dart";
import "package:bobomusic/features/settings/update_checker.dart";
import "package:flutter_test/flutter_test.dart";

/// S5 更新检查纯函数（D5：旧版 2.x tag 不能被判成“更新”）
void main() {
  group("compareVersions", () {
    test("3.0.0 高于 2.7.0（旧正式版不会被误判为更新）", () {
      expect(compareVersions("3.0.0", "2.7.0"), greaterThan(0));
      expect(compareVersions("2.7.0", "3.0.0"), lessThan(0));
    });

    test("v 前缀、段数补齐与 build/后缀忽略", () {
      expect(compareVersions("v3.0.0", "3.0.0"), 0);
      expect(compareVersions("3.0", "3.0.0"), 0);
      expect(compareVersions("3.0.0+300", "3.0.0"), 0);
      expect(compareVersions("3.0.1", "3.0.0"), greaterThan(0));
      expect(compareVersions("2.10.0", "2.7.0"), greaterThan(0));
    });

    test("patch 位比较", () {
      expect(compareVersions("3.0.10", "3.0.9"), greaterThan(0));
      expect(compareVersions("3.1.0", "3.0.99"), greaterThan(0));
    });
  });

  group("pickLatestRelease / AppRelease", () {
    AppRelease release(String tag) => AppRelease.fromJson({
          "tag_name": tag,
          "html_url": "https://github.com/Redstone-1/bobomusic/releases/tag/$tag",
          "body": "notes-$tag",
          "published_at": "2026-10-01T00:00:00Z",
        });

    test("取版本号最高的一条", () {
      final latest = pickLatestRelease([
        release("v2.7.0"),
        release("v3.1.0"),
        release("v3.0.5"),
      ]);
      expect(latest?.version, "3.1.0");
      expect(latest?.tag, "v3.1.0");
      expect(latest?.notes, "notes-v3.1.0");
    });

    test("空列表返回 null；normalizeVersion 去 v", () {
      expect(pickLatestRelease(const []), isNull);
      expect(normalizeVersion("v3.0.0"), "3.0.0");
      expect(normalizeVersion("3.0.0"), "3.0.0");
    });
  });

  group("gitee release 解析（检查更新主链）", () {
    test("html_url 缺失回填 releases 列表页，时间回退 created_at", () {
      final release = appReleaseFromGiteeJson({
        "tag_name": "v3.1.0",
        "body": "gitee notes",
        "created_at": "2026-11-01T10:00:00+08:00",
      }, fallbackUrl: "https://gitee.com/redstone-1/bobomusic/releases");
      expect(release.version, "3.1.0");
      expect(release.tag, "v3.1.0");
      expect(release.url, "https://gitee.com/redstone-1/bobomusic/releases");
      expect(release.notes, "gitee notes");
      expect(release.publishedAt, "2026-11-01T10:00:00+08:00");
    });

    test("带 html_url 时优先使用", () {
      final release = appReleaseFromGiteeJson({
        "tag_name": "3.2.0",
        "html_url": "https://gitee.com/redstone-1/bobomusic/releases/1",
      }, fallbackUrl: "ignored");
      expect(release.url, "https://gitee.com/redstone-1/bobomusic/releases/1");
    });
  });

  test("GitHub 列表解析：过滤 draft/prerelease 与脏数据", () {
    final releases = parseGithubReleases([
      {"tag_name": "v3.1.0", "html_url": "https://x/1"},
      {"tag_name": "v3.2.0-rc", "prerelease": true, "html_url": "https://x/2"},
      {"tag_name": "v3.3.0", "draft": true, "html_url": "https://x/3"},
      {"tag_name": "", "html_url": "https://x/4"},
      "junk",
    ]);
    expect(releases, hasLength(1));
    expect(releases.single.version, "3.1.0");
  });

  group("formatBytes", () {
    test("B / KB / MB / GB", () {
      expect(formatBytes(0), "0 B");
      expect(formatBytes(512), "512 B");
      expect(formatBytes(1024), "1.0 KB");
      expect(formatBytes(1024 * 1024 * 3 ~/ 2), "1.5 MB");
      expect(formatBytes(1024 * 1024 * 1024 * 2), "2.0 GB");
    });
  });
}
