import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/song_list_tile.dart";
import "../../data/models/queue_entry.dart";
import "../../data/models/track.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../playlist/playlists_provider.dart" show queueEntriesProvider;
import "../playlist/track_edit_dialog.dart";
import "playback_provider.dart";

void showPlaybackQueueSheet(BuildContext context) {
  AppSheet.show(context, child: const _PlaybackQueueSheet());
}

/// 待播条目和当前会话分别操作，歌曲身份不能替代一次排队记录的身份。
class _PlaybackQueueSheet extends ConsumerStatefulWidget {
  const _PlaybackQueueSheet();

  @override
  ConsumerState<_PlaybackQueueSheet> createState() =>
      _PlaybackQueueSheetState();
}

class _PlaybackQueueSheetState extends ConsumerState<_PlaybackQueueSheet> {
  bool _busy = false;

  Future<void> _play(Future<bool> Function(Playback) command) async {
    if (_busy) return;
    final playback = ref.read(playbackProvider.notifier);
    setState(() => _busy = true);
    try {
      final success = await command(playback);
      if (mounted && success) Navigator.of(context).pop();
    } catch (e) {
      print("队列点播失败：$e");
      if (mounted) AppToast.show(context, "播放失败，请重试");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mutate(Future<bool> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await action();
      if (mounted) {
        AppToast.show(context, changed ? success : "该条目已播放或移除");
      }
    } catch (e) {
      print("更新播放队列失败：$e");
      if (mounted) AppToast.show(context, "队列更新失败，请重试");
    } finally {
      if (mounted) {
        ref.invalidate(queueEntriesProvider);
        setState(() => _busy = false);
      }
    }
  }

  void _pendingActions(QueueEntry entry) {
    AppSheet.show(
      context,
      title: entry.track.effectiveName,
      actions: [
        AppSheetAction(
          icon: Icons.edit_outlined,
          label: "编辑信息",
          onTap: () => showTrackEditDialog(context, ref, entry.track),
        ),
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: "下一首播放",
          onTap: () => _mutate(
            () => QueueRepository().moveEntryToFront(entry.id),
            "已设为下一首播放",
          ),
        ),
        AppSheetAction(
          icon: Icons.playlist_remove,
          label: "移除本条",
          danger: true,
          onTap: () => _mutate(
            () => QueueRepository().removeEntry(entry.id),
            "已移除待播放条目",
          ),
        ),
      ],
    );
  }

  void _sessionActions(Track track, int index, List<Track> snapshot) {
    final currentIndex = ref.read(playbackProvider).queueIndex;
    AppSheet.show(
      context,
      title: track.effectiveName,
      actions: [
        AppSheetAction(
          icon: Icons.edit_outlined,
          label: "编辑信息",
          onTap: () => showTrackEditDialog(context, ref, track),
        ),
        AppSheetAction(
          icon: Icons.queue_music_outlined,
          label: "下一首播放",
          onTap: () => _mutate(() async {
            await TrackRepository().upsert(track);
            await QueueRepository().insertNext(track.id);
            return true;
          }, "已设为下一首播放"),
        ),
        // 当前条目保持播放，其它条目可按会话下标独立移除。
        if (index != currentIndex)
          AppSheetAction(
            icon: Icons.playlist_remove,
            label: "移除本条",
            danger: true,
            onTap: () {
              final removed = ref
                  .read(playbackProvider.notifier)
                  .removeSessionEntry(index, expectedQueue: snapshot);
              if (removed) AppToast.show(context, "已从播放队列移除");
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 进度和倍速不影响列表，只订阅会话结构和当前曲目。
    final session = ref.watch(playbackProvider.select((state) => (
          queue: state.queue,
          index: state.queueIndex,
          trackId: state.track?.id,
        )));
    final pending = ref.watch(queueEntriesProvider);
    final entries = pending.value;
    final tokens = AuroraTokens.of(context);
    final count = session.queue.length;
    return SizedBox(
      key: const Key("playback_queue_sheet"),
      height: (MediaQuery.sizeOf(context).height * 0.65)
          .clamp(0.0, 480.0)
          .toDouble(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "播放队列 · $count 首",
                key: const Key("playback_queue_title"),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                const _QueueSectionHeader("待播放 · 当前曲播完后依次播出"),
                if (entries == null)
                  if (pending.hasError)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _QueueMessage("待播放加载失败"),
                        TextButton(
                          onPressed: () => ref.invalidate(queueEntriesProvider),
                          child: const Text("重试"),
                        ),
                      ],
                    )
                  else
                    const _QueueMessage("待播放加载中…")
                else if (entries.isEmpty)
                  const _QueueMessage("暂无待播放歌曲")
                else
                  for (final entry in entries)
                    _pendingTile(entry, session.trackId),
                _QueueSectionHeader("播放队列 · $count 首"),
                for (final (index, track) in session.queue.indexed)
                  SongListTile(
                    key: ValueKey("session_$index"),
                    track: track,
                    playing: index == session.index,
                    onTap: _busy
                        ? null
                        : () => _play(
                              (playback) => playback.playSessionEntry(index,
                                  expectedQueue: session.queue),
                            ),
                    onMorePressed: _busy
                        ? null
                        : () => _sessionActions(track, index, session.queue),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingTile(QueueEntry entry, String? currentTrackId) {
    final id = entry.id;
    return SongListTile(
      key: ValueKey("pending_$id"),
      track: entry.track,
      playing: entry.track.id == currentTrackId,
      onTap: _busy
          ? null
          : () => _play((playback) => playback.playQueuedEntry(entry.id)),
      onMorePressed: _busy ? null : () => _pendingActions(entry),
    );
  }
}

class _QueueSectionHeader extends StatelessWidget {
  final String label;
  const _QueueSectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final tokens = AuroraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: tokens.fgDim)),
    );
  }
}

class _QueueMessage extends StatelessWidget {
  final String message;
  const _QueueMessage(this.message);

  @override
  Widget build(BuildContext context) {
    final tokens = AuroraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child:
          Text(message, style: TextStyle(fontSize: 12, color: tokens.fgMute)),
    );
  }
}
