import "package:dio/dio.dart";

/// 一条 GitHub Release（只保留稳定版；D5：按版本号比较，避免旧 tag 误判）
class AppRelease {
  final String version;
  final String tag;
  final String url;
  final String notes;
  final String publishedAt;

  const AppRelease({
    required this.version,
    required this.tag,
    required this.url,
    required this.notes,
    required this.publishedAt,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = "${json["tag_name"] ?? ""}";
    return AppRelease(
      version: normalizeVersion(tag),
      tag: tag,
      url: "${json["html_url"] ?? ""}",
      notes: "${json["body"] ?? ""}",
      publishedAt: "${json["published_at"] ?? ""}",
    );
  }
}

class UpdateResult {
  final String currentVersion;
  final AppRelease? latest;
  final bool hasUpdate;

  const UpdateResult({
    required this.currentVersion,
    required this.latest,
    required this.hasUpdate,
  });
}

/// 检查更新（D5：按版本号比较，避免旧 tag 误判）。
/// 主链 gitee Releases（国内免登录稳定；由所有者在 gitee 手动发版），
/// 失败回退 GitHub Releases——匿名 API 每 IP 60 次/时限流，403 是常态
class UpdateChecker {
  static const _giteeRepo = "redstone-1/bobomusic";
  static const _githubRepo = "Redstone-1/bobomusic";
  static const _giteeReleasesPage = "https://gitee.com/$_giteeRepo/releases";

  static final Dio _giteeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {"User-Agent": "bobomusic"},
    ),
  );

  static final Dio _githubDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        "Accept": "application/vnd.github+json",
        "User-Agent": "bobomusic",
      },
    ),
  );

  Future<UpdateResult> check(String currentVersion) async {
    try {
      return _pick(currentVersion, await _fetchGitee());
    } catch (e) {
      print("gitee 检查更新失败，回退 GitHub：$e");
    }
    return _pick(currentVersion, await _fetchGithub());
  }

  UpdateResult _pick(String currentVersion, List<AppRelease> releases) {
    final latest = pickLatestRelease(releases);
    return UpdateResult(
      currentVersion: currentVersion,
      latest: latest,
      hasUpdate:
          latest != null && compareVersions(latest.version, currentVersion) > 0,
    );
  }

  /// gitee releases 列表（尚无正式版时返回空列表，按"已是最新"处理）
  Future<List<AppRelease>> _fetchGitee() async {
    final response = await _giteeDio.get(
      "https://gitee.com/api/v5/repos/$_giteeRepo/releases",
      queryParameters: {"per_page": "20"},
    );
    final raw = response.data is List ? response.data as List : const [];
    final releases = <AppRelease>[];
    for (final item in raw) {
      if (item is! Map) continue;
      if (item["draft"] == true || item["prerelease"] == true) continue;
      final release = appReleaseFromGiteeJson(
        item.cast<String, dynamic>(),
        fallbackUrl: _giteeReleasesPage,
      );
      if (release.version.isEmpty || release.url.isEmpty) continue;
      releases.add(release);
    }
    return releases;
  }

  Future<List<AppRelease>> _fetchGithub() async {
    final response = await _githubDio.get(
      "https://api.github.com/repos/$_githubRepo/releases",
      queryParameters: {"per_page": "20"},
    );
    final raw = response.data is List ? response.data as List : const [];
    return parseGithubReleases(raw);
  }
}

/// 全局可替换（测试注入固定版本/跳过网络）
UpdateChecker updateChecker = UpdateChecker();

/// gitee release JSON → AppRelease（纯函数便于测试）。
/// gitee 对象没有 html_url 字段：为空时回填 [fallbackUrl]（releases 列表页）
AppRelease appReleaseFromGiteeJson(Map json, {String fallbackUrl = ""}) {
  final tag = "${json["tag_name"] ?? ""}".trim();
  final htmlUrl = "${json["html_url"] ?? ""}".trim();
  return AppRelease(
    version: normalizeVersion(tag),
    tag: tag,
    url: htmlUrl.isEmpty ? fallbackUrl : htmlUrl,
    notes: "${json["body"] ?? ""}",
    publishedAt: "${json["published_at"] ?? json["created_at"] ?? ""}",
  );
}

/// GitHub releases 响应 → 稳定版列表（纯函数便于测试：
/// 过滤 draft/prerelease 与无 tag/无跳转地址的脏数据）
List<AppRelease> parseGithubReleases(List raw) {
  final releases = <AppRelease>[];
  for (final item in raw) {
    if (item is! Map) continue;
    if (item["draft"] == true || item["prerelease"] == true) continue;
    final release = AppRelease.fromJson(item.cast<String, dynamic>());
    if (release.version.isEmpty || release.url.isEmpty) continue;
    releases.add(release);
  }
  return releases;
}

/// 取版本号最高的稳定 release（同版本保留先出现项）
AppRelease? pickLatestRelease(List<AppRelease> releases) {
  AppRelease? best;
  for (final release in releases) {
    if (best == null || compareVersions(release.version, best.version) > 0) {
      best = release;
    }
  }
  return best;
}

/// 语义版本比较（只比较数字段；忽略 v 前缀、+build 与 -pre 后缀）
/// 返回 >0 表示 a 更新，<0 表示 b 更新，0 相同
int compareVersions(String a, String b) {
  final pa = _versionParts(a);
  final pb = _versionParts(b);
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _versionParts(String input) {
  var text = input.trim();
  if (text.startsWith("v") || text.startsWith("V")) {
    text = text.substring(1);
  }
  text = text.split("+").first.split("-").first;
  return [
    for (final part in text.split("."))
      int.tryParse(part.replaceAll(RegExp(r"[^0-9]"), "")) ?? 0,
  ];
}

String normalizeVersion(String tag) {
  var text = tag.trim();
  if (text.startsWith("v") || text.startsWith("V")) {
    text = text.substring(1);
  }
  return text;
}
