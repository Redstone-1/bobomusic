import "dart:io";

import "package:bobomusic/data/local_audio_importer.dart";
import "package:bobomusic/data/local_audio_scanner.dart";
import "package:bobomusic/data/models/track.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;

class _FakeMeta implements AudioMetadataSource {
  @override
  RawAudioMeta read(File file) => RawAudioMeta(
        title: p.basenameWithoutExtension(file.path),
        artist: "导入歌手",
        durationMs: 120000,
      );
}

void main() {
  test("导入文件：复制到目标目录、生成 local 曲目、重复导入 id 稳定", () async {
    final temp = await Directory.systemTemp.createTemp("bobo_import_test");
    addTearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    });
    final srcDir = Directory(p.join(temp.path, "src"))
      ..createSync(recursive: true);
    final a = File(p.join(srcDir.path, "a.mp3"))..writeAsStringSync("AAA");
    final b = File(p.join(srcDir.path, "b.flac"))..writeAsStringSync("BBBB");
    final target = Directory(p.join(temp.path, "imported"));

    final first = await importAudioFilePaths(
      [a.path, b.path],
      targetDir: target,
      source: _FakeMeta(),
    );

    expect(first.length, 2);
    expect(first.every((t) => t.origin == OriginType.local), isTrue);
    expect(first.every((t) => File(t.localPath!).existsSync()), isTrue);
    expect(first.map((t) => t.name).toSet(), {"a", "b"});

    // 同文件再次导入：内容指纹不变（喜欢/歌词可保留）
    final second = await importAudioFilePaths(
      [a.path, b.path],
      targetDir: target,
      source: _FakeMeta(),
    );
    expect(second.map((t) => t.id).toSet(), first.map((t) => t.id).toSet());

    // 只导入新文件：本次数量应为 1，不把历史导入条目重复计数
    final c = File(p.join(srcDir.path, "c.mp3"))..writeAsStringSync("CC");
    final third = await importAudioFilePaths(
      [c.path],
      targetDir: target,
      source: _FakeMeta(),
    );
    expect(third.length, 1);
    expect(third.single.name, "c");
  });

  test("不存在的源文件静默跳过，不影响其它文件", () async {
    final temp = await Directory.systemTemp.createTemp("bobo_import_test2");
    addTearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    });
    final valid = File(p.join(temp.path, "ok.mp3"))..writeAsStringSync("OK");
    final tracks = await importAudioFilePaths(
      [p.join(temp.path, "missing.mp3"), valid.path],
      targetDir: Directory(p.join(temp.path, "out")),
      source: _FakeMeta(),
    );
    expect(tracks.length, 1);
    expect(tracks.single.name, "ok");
  });

  test("同名不同内容另存，相同内容再次导入复用已保存文件", () async {
    final temp = await Directory.systemTemp.createTemp("bobo_same_name");
    addTearDown(() => temp.delete(recursive: true));
    final a = File(p.join(temp.path, "a", "同名.mp3"));
    final b = File(p.join(temp.path, "b", "同名.mp3"));
    await a.parent.create();
    await b.parent.create();
    await a.writeAsString("AAA");
    await b.writeAsString("BBB");
    final target = Directory(p.join(temp.path, "导入 目录"));
    final first = await importAudioFilePaths([a.path, b.path],
        targetDir: target, source: _FakeMeta());
    expect(first.map((track) => track.localPath).toSet().length, 2);
    expect(await File(first.first.localPath!).readAsString(), "AAA");
    expect(await File(first.last.localPath!).readAsString(), "BBB");
    final again = await importAudioFilePaths([b.path],
        targetDir: target, source: _FakeMeta());
    expect(again.single.localPath, first.last.localPath);
    expect(await target.list().length, 2);
  });
}
