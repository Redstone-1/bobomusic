import "dart:io";

import "package:bobomusic/data/local_audio_scanner.dart";
import "package:flutter_test/flutter_test.dart";

/// C3 扫描器单测：注入 fake 元数据源（主 isolate 直跑），不依赖真音频文件
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync("bobo_scan_test");
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File touch(String relativePath) {
    final file = File("${tmp.path}/$relativePath");
    file.createSync(recursive: true);
    return file;
  }

  /// 按路径末段返回固定元数据；标记 bad 的文件抛异常模拟解析失败
  AudioMetadataSource fakeSource({Set<String> bad = const {}}) {
    return _FakeSource(bad);
  }

  test("内容指纹：标题/歌手归一化（大小写与多余空白不敏感）", () {
    final a = localAudioFingerprint(
        sizeBytes: 100, durationSec: 60, title: "夜 曲", artist: "Liu Shuang");
    final b = localAudioFingerprint(
        sizeBytes: 100, durationSec: 60, title: "夜曲", artist: "liu shuang");
    final c = localAudioFingerprint(
        sizeBytes: 101, durationSec: 60, title: "夜曲", artist: "liu shuang");
    expect(a, b); // 归一化后一致
    expect(a, isNot(c)); // 大小不同 → 身份不同
    expect(a.startsWith("local:"), isTrue);
  });

  test("目录排除规则：Android 系统目录与 App 下载目录", () {
    expect(LocalAudioScanner.isExcludedDir(Directory("/storage/emulated/0/Android/data")), isTrue);
    expect(LocalAudioScanner.isExcludedDir(Directory("/storage/emulated/0/Download/啵啵音乐")), isTrue);
    // Windows 分隔符同样识别
    expect(LocalAudioScanner.isExcludedDir(Directory("C:\\x\\Android")), isTrue);
    expect(LocalAudioScanner.isExcludedDir(Directory("/storage/emulated/0/Download")), isFalse);
    expect(LocalAudioScanner.isExcludedDir(Directory("/storage/emulated/0/Music")), isFalse);
  });

  test("扫描：扩展名过滤 + 排除目录 + 失败收集 + 标题回退文件名", () async {
    final good = touch("a.mp3");
    touch("sub/b.txt"); // 非音频
    touch("Android/c.mp3"); // 系统目录
    touch("Download/啵啵音乐/d.mp3"); // App 下载目录
    touch("Download/e.mp3"); // Download 本体不排除
    touch("no_meta.flac"); // 元数据缺失 → 回退文件名
    touch("bad.ogg"); // 解析失败

    final result = await LocalAudioScanner().scan(
      roots: [tmp],
      source: fakeSource(bad: {"bad.ogg"}),
    );

    expect(result.tracks.length, 3); // a / e / no_meta
    expect(
      result.tracks.map((t) => t.name).toSet(),
      {"标题A", "标题E", "no_meta"}, // no_meta 回退文件名
    );
    expect(
      result.tracks.every((t) => t.origin.name == "local" && t.id.startsWith("local:")),
      isTrue,
    );
    expect(
      result.tracks.every((t) => t.localPath != null && t.localPath!.contains(tmp.path)),
      isTrue,
    );
    expect(result.failed.length, 1);
    expect(result.failed.single.endsWith("bad.ogg"), isTrue);
    expect(good.existsSync(), isTrue); // 只读扫描，不动文件
  });

  test("重复扫描同目录：指纹 id 稳定（§3.4-9 重扫不丢喜欢/歌词的前提）", () async {
    touch("a.mp3");
    touch("b.m4a");
    final first = await LocalAudioScanner().scan(roots: [tmp], source: fakeSource());
    final second = await LocalAudioScanner().scan(roots: [tmp], source: fakeSource());
    expect(
      second.tracks.map((t) => t.id).toSet(),
      first.tracks.map((t) => t.id).toSet(),
    );
  });

  test("歌手缺失记「未知歌手」", () async {
    touch("a.mp3");
    final result = await LocalAudioScanner().scan(
      roots: [tmp],
      source: _FakeSource(const <String>{}, emptyArtist: true),
    );
    expect(result.tracks.single.author, "未知歌手");
  });
}

class _FakeSource implements AudioMetadataSource {
  final Set<String> bad;
  final bool emptyArtist;

  const _FakeSource(this.bad, {this.emptyArtist = false});

  @override
  RawAudioMeta read(File file) {
    final name = file.path.replaceAll("\\", "/").split("/").last;
    if (bad.contains(name)) throw const FileSystemException("解析失败");
    if (name == "a.mp3") {
      return RawAudioMeta(
        title: "标题A",
        artist: emptyArtist ? "" : "歌手A",
        durationMs: 61000,
      );
    }
    if (name == "e.mp3") {
      return RawAudioMeta(title: "标题E", artist: "歌手E", durationMs: 3000);
    }
    return const RawAudioMeta(); // 其余文件元数据缺失
  }
}
