import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/prefs/app_prefs.dart";

/// 默认搜索音源（D11：设置中切换 B 站 / 酷我；暂不做失败自动回退）
enum MusicSource {
  bili("B 站"),
  kuwo("酷我");

  final String label;
  const MusicSource(this.label);
}

const _key = "music_source";

final musicSourceProvider =
    NotifierProvider<MusicSourceController, MusicSource>(
  MusicSourceController.new,
);

class MusicSourceController extends Notifier<MusicSource> {
  @override
  MusicSource build() {
    final name = appPrefs.getString(_key);
    return name == MusicSource.kuwo.name ? MusicSource.kuwo : MusicSource.bili;
  }

  void select(MusicSource source) {
    if (state == source) return;
    state = source;
    appPrefs.setString(_key, source.name);
  }
}
