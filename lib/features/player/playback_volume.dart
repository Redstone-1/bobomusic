const playbackVolumePreferenceKey = "playback_volume";
const playbackLastVolumePreferenceKey = "playback_last_audible_volume";

/// 音量是应用偏好，损坏值不能传给平台引擎或 Slider。
double restorePlaybackVolume(Object? value) =>
    value is num && value.isFinite && value >= 0 && value <= 1
        ? value.toDouble()
        : 1;
