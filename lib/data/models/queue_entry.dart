import "track.dart";

/// 一次独立排队记录；同一首歌可以出现多次，菜单操作只针对该 id。
class QueueEntry {
  final int id;
  final Track track;

  const QueueEntry({required this.id, required this.track});
}
