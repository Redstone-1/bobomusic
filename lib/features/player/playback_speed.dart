/// 播放卡预设档位；系统媒体命令可在同一范围内设置其它速度。
const playbackSpeedPresets = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const playbackSpeedPreferenceKey = "playback_speed";

bool isValidPlaybackSpeed(double speed) =>
    speed.isFinite && speed >= 0.5 && speed <= 2.0;

/// 旧偏好缺失或损坏时恢复正常速度，不让异常值进入原生播放器。
double restorePlaybackSpeed(Object? value) {
  if (value is! num) return 1.0;
  final speed = value.toDouble();
  return isValidPlaybackSpeed(speed) ? speed : 1.0;
}

String playbackSpeedLabel(double speed) {
  final text = speed.toStringAsFixed(2);
  return "${text.endsWith("0") ? text.substring(0, text.length - 1) : text}×";
}
