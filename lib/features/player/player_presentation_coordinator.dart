import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";

import "../playlist/playlists_provider.dart";
import "lyric_provider.dart";
import "playback_provider.dart";

/// 播放关联的加载放在常驻 provider 中，侧栏收起或页面隐藏都不会中断歌词与历史更新。
final playerPresentationCoordinatorProvider = Provider<void>((ref) {
  ref.listen(playbackProvider.select((state) => state.track), (_, track) {
    if (track == null) return;
    Future.microtask(() async {
      if (!ref.mounted) return;
      ref.invalidate(recentTracksProvider);
      try {
        await ref.read(lyricControllerProvider.notifier).loadFor(track);
      } catch (error) {
        print("加载当前歌曲歌词失败：$error");
      }
    });
  }, fireImmediately: true);
});
