import "dart:async";

import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../core/prefs/app_prefs.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../data/repositories/track_repository.dart";
import "audio_engine.dart";
import "play_mode.dart";

part "playback_provider.g.dart";

/// 播放状态（UI 全量消费；高频字段 position 用 select 订阅避免整卡重建）
class PlaybackState {
  final Track? track;

  /// 会话队列与当前下标（§3.4-4：队列 = 点播时所在列表）
  final List<Track> queue;
  final int queueIndex;

  final bool playing;
  final bool buffering;

  /// 装载/播放出错（引擎层类型化错误；UI listen 弹提示，§5.3-3）
  final String? error;

  final Duration position;
  final Duration duration;
  final PlayMode mode;

  const PlaybackState({
    this.track,
    this.queue = const [],
    this.queueIndex = -1,
    this.playing = false,
    this.buffering = false,
    this.error,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.mode = PlayMode.listLoop,
  });

  PlaybackState copyWith({
    Track? track,
    List<Track>? queue,
    int? queueIndex,
    bool? playing,
    bool? buffering,
    String? error,
    Duration? position,
    Duration? duration,
    PlayMode? mode,
    bool clearError = false,
  }) =>
      PlaybackState(
        track: track ?? this.track,
        queue: queue ?? this.queue,
        queueIndex: queueIndex ?? this.queueIndex,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        error: clearError ? null : error ?? this.error,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        mode: mode ?? this.mode,
      );
}

/// 可替换全局（测试模式）：注入引擎与直链解析，FakeEngine 下全链路可测；
/// [randomPick] 随机模式的取数函数（测试注入固定序列，生产用真随机）
class PlaybackDeps {
  final AudioEngine engine;
  final Future<String> Function(Track track) resolveUrl;
  final int Function(int max)? randomPick;

  const PlaybackDeps({
    required this.engine,
    required this.resolveUrl,
    this.randomPick,
  });
}

PlaybackDeps? playbackDepsTestOverride;

const _kTrackId = "playback_track_id";
const _kPositionMs = "playback_position_ms";
const _kMode = "playback_mode";

/// 播放状态机（§5.2-1：PlaySession + NextStrategy；引擎只做"取下一首→装载→播放"）
/// 断点续播：进度去抖 5s 写盘，暂停/切歌/销毁立即写（§5.2-2）
@Riverpod(keepAlive: true)
class Playback extends _$Playback {
  AudioEngine? _engine;
  StreamSubscription? _onPosition;
  StreamSubscription? _onDuration;
  StreamSubscription? _onPlaying;
  StreamSubscription? _onCompletion;
  StreamSubscription? _onError;
  Timer? _persistDebounce;
  bool _restored = false;

  /// 惰性创建并订阅事件流（首次使用时；dispose 统一取消）
  AudioEngine _resolveEngine() {
    if (_engine != null) return _engine!;
    final e = playbackDepsTestOverride?.engine;
    // A2 接入真实现（just_audio + audio_service）前，生产路径不可构造；
    // UI 在 B 批换真 provider 前不会引用本 provider
    if (e == null) throw UnimplementedError("A2 接入 JustAudioEngine");
    _engine = e;
    _subscribe(e);
    return e;
  }

  @override
  PlaybackState build() {
    ref.onDispose(_dispose);
    _restoreFromPrefs();
    return const PlaybackState();
  }

  /// 点播：以 [queue]（默认单曲）为会话队列播放 [track]
  Future<void> play(Track track, {List<Track>? queue}) async {
    final sessionQueue = (queue == null || queue.isEmpty) ? [track] : queue;
    final index = sessionQueue.indexWhere((t) => t.id == track.id);
    await _load(
      sessionQueue,
      index < 0 ? 0 : index,
      autoplay: true,
    );
  }

  Future<void> toggle() async {
    if (state.track == null) return;
    if (state.playing) {
      await _resolveEngine().pause();
    } else {
      await _resolveEngine().play();
    }
  }

  Future<void> pause() async {
    if (!state.playing) return;
    await _resolveEngine().pause();
    _persistNow();
  }

  Future<void> seek(Duration position) async {
    await _resolveEngine().seek(position);
    state = state.copyWith(position: position);
    _snapshot();
    _persistDebounced();
  }

  /// 循环切换播放模式（UI toast 文案取 label）
  Future<void> cycleMode() async {
    state = state.copyWith(mode: state.mode.next);
    _snapshot();
    appPrefs.setString(_kMode, state.mode.name);
  }

  Future<void> next() => _jump(auto: false, backward: false);

  Future<void> previous() => _jump(auto: false, backward: true);

  /// 播完自动切歌的入口（completion 事件触发）
  Future<void> _onCompleted() => _jump(auto: true, backward: false);

  Future<void> _jump({required bool auto, required bool backward}) async {
    final queue = state.queue;
    final target = nextIndex(
      mode: state.mode,
      current: state.queueIndex,
      queueLength: queue.length,
      auto: auto,
      backward: backward,
      randomPick: playbackDepsTestOverride?.randomPick,
    );
    _persistNow();
    if (target == null) {
      // 顺序模式到队尾（或队列空）：自然停止
      await _resolveEngine().stop();
      state = state.copyWith(playing: false, position: Duration.zero);
      _snapshot();
      return;
    }
    await _load(queue, target, autoplay: true);
  }

  Future<void> _load(
    List<Track> queue,
    int index, {
    required bool autoplay,
    Duration? initialPosition,
  }) async {
    final track = queue[index];
    state = state.copyWith(
      track: track,
      queue: queue,
      queueIndex: index,
      buffering: true,
      position: initialPosition ?? Duration.zero,
      duration: Duration.zero,
      clearError: true,
    );
    _snapshot();
    try {
      final url = await _resolveUrl(track);
      await _resolveEngine().load(
        url,
        initialPosition: initialPosition,
      );
      if (autoplay) await _resolveEngine().play();
    } catch (e) {
      // 装载失败：类型化错误上抛到 state（UI 提示），不静默挂死（§5.1-2）
      state = state.copyWith(buffering: false, playing: false, error: "$e");
    }
  }

  Future<String> _resolveUrl(Track track) async {
    final override = playbackDepsTestOverride;
    if (override != null) return override.resolveUrl(track);
    final musicUrl = await biliApi.getMusicUrl(track.id);
    return musicUrl.url;
  }

  void _subscribe(AudioEngine e) {
    _onPosition = e.positionStream.listen(
      (p) {
        if (!state.buffering) state = state.copyWith(position: p);
        _snapshot();
        _persistDebounced();
      },
    );
    _onDuration = e.durationStream.listen(
      (d) => state = state.copyWith(duration: d),
    );
    _onPlaying = e.playingStream.listen(
      (playing) => state = state.copyWith(
        playing: playing,
        buffering: false,
      ),
    );
    _onCompletion = e.completionStream.listen((_) => _onCompleted());
    _onError = e.errorStream.listen((err) {
      state = state.copyWith(
        buffering: false,
        playing: false,
        error: "$err",
      );
    });
  }

  /// 进度去抖 5s 写盘（§5.2-2：修掉旧版"每秒写盘"与"假节流"两个极端）
  void _persistDebounced() {
    if (state.track == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 5), _persistNow);
  }

  /// 持久化快照（onDispose 回调里禁止读 state，缓存字段供全路径安全写盘）
  Track? _snapTrack;
  Duration _snapPosition = Duration.zero;
  PlayMode _snapMode = PlayMode.listLoop;

  void _snapshot() {
    if (state.track != null) _snapTrack = state.track;
    _snapPosition = state.position;
    _snapMode = state.mode;
  }

  void _persistNow() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    final track = _snapTrack;
    if (track == null) return;
    appPrefs.setString(_kTrackId, track.id);
    appPrefs.setInt(_kPositionMs, _snapPosition.inMilliseconds);
    appPrefs.setString(_kMode, _snapMode.name);
  }

  /// 冷启动断点恢复：曲目/进度/模式回填（暂停态；点播放续播），
  /// 队列恢复走 queue 表（B 批接线时补）
  Future<void> _restoreFromPrefs() async {
    if (_restored) return;
    _restored = true;
    final trackId = appPrefs.getString(_kTrackId);
    if (trackId == null) return;
    final modeName = appPrefs.getString(_kMode);
    final positionMs = appPrefs.getInt(_kPositionMs) ?? 0;
    final track = await TrackRepository().getById(trackId);
    if (track == null) return;
    state = state.copyWith(
      track: track,
      queue: [track],
      queueIndex: 0,
      position: Duration(milliseconds: positionMs),
      mode: PlayMode.values
          .where((m) => m.name == modeName)
          .firstOrNull ?? PlayMode.listLoop,
    );
    _snapshot();
  }

  void _dispose() {
    _persistNow();
    _onPosition?.cancel();
    _onDuration?.cancel();
    _onPlaying?.cancel();
    _onCompletion?.cancel();
    _onError?.cancel();
    _persistDebounce?.cancel();
  }
}
