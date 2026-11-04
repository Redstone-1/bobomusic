import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/widgets/empty_state.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/repositories/history_repository.dart";
import "../player/playback_provider.dart";
import "playlists_provider.dart";
import "track_edit_dialog.dart";

class RecentTracksPage extends ConsumerWidget {
  const RecentTracksPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTracksProvider);
    final currentId = ref.watch(playbackProvider.select((s) => s.track?.id));
    final playingNow = ref.watch(playbackProvider.select((s) => s.playing));
    return ListView(padding: const EdgeInsets.all(28), children: [
      PageHeader(
          title: "最近播放",
          subtitle: "让好听的歌再次相遇",
          trailing: TextButton(
              onPressed: recent.value?.isNotEmpty != true
                  ? null
                  : () async {
                      final confirmed = await AppDialog.confirm(context,
                          title: "清空最近播放",
                          message: "只清空播放记录，不删除歌曲或歌单。",
                          confirmText: "清空");
                      if (confirmed == true) {
                        await HistoryRepository().clear();
                        ref.invalidate(recentTracksProvider);
                      }
                    },
              child: const Text("清空"))),
      const SizedBox(height: 20),
      recent.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => EmptyState(
              title: "播放记录加载失败",
              subtitle: "$error",
              action: TextButton(
                  onPressed: () => ref.invalidate(recentTracksProvider),
                  child: const Text("重试"))),
          data: (tracks) => tracks.isEmpty
              ? const EmptyState(
                  asset: "assets/illustrations/empty_music.svg",
                  title: "还没有播放记录",
                  subtitle: "播放过的音乐会出现在这里")
              : Column(children: [
                  for (final track in tracks)
                    SongListTile(
                        track: track,
                        playing: track.id == currentId,
                        paused: !playingNow,
                        onTap: () => ref.read(playbackProvider.notifier).play(track, queue: tracks),
                        onMorePressed: () =>
                            showTrackEditDialog(context, ref, track)),
                ])),
    ]);
  }
}
