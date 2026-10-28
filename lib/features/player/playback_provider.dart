import "dart:async";
import "dart:convert";
import "dart:io";

import "package:riverpod_annotation/riverpod_annotation.dart";

import "../../core/prefs/app_prefs.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../data/repositories/history_repository.dart";
import "../../data/repositories/queue_repository.dart";
import "../../data/repositories/track_repository.dart";
import "../../origin_sdk/bili/bili_api_error.dart";
import "../playlist/playlists_provider.dart" show queueTracksProvider;
import "audio_engine.dart";
import "just_audio_engine.dart";
import "play_mode.dart";
import "playback_audio_handler.dart";

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

  /// 定时关闭截止时间（null = 未开启；仅会话内有效，不持久化）
  final DateTime? sleepDeadline;

  /// 播完当前曲后停止（定时关闭的「播完再停」模式）
  final bool stopAfterTrack;

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
    this.sleepDeadline,
    this.stopAfterTrack = false,
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
    DateTime? sleepDeadline,
    bool clearSleep = false,
    bool? stopAfterTrack,
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
        sleepDeadline:
            clearSleep ? null : sleepDeadline ?? this.sleepDeadline,
        stopAfterTrack: stopAfterTrack ?? this.stopAfterTrack,
      );
}

/// 可替换全局（测试模式）：注入引擎与源解析，FakeEngine 下全链路可测；
/// [randomPick] 随机模式的取数函数（测试注入固定序列，生产用真随机）
class PlaybackDeps {
  final AudioEngine engine;

  /// 测试可只注入引擎、保留生产源解析（如验证本地文件优先）
  final Future<PlaySource> Function(Track track)? resolveSource;
  final int Function(int max)? randomPick;

  const PlaybackDeps({
    required this.engine,
    this.resolveSource,
    this.randomPick,
  });
}

PlaybackDeps? playbackDepsTestOverride;

const _kTrackId = "playback_track_id";
const _kPositionMs = "playback_position_ms";
const _kMode = "playback_mode";

/// 会话队列快照（id 列表 JSON + 当前下标）：跨启动恢复点歌列表上下文，
/// 与插队/稍后听的 queue 表互不相干（queue 表自身持久，由 takeFirst 消费）
const _kQueueIds = "playback_queue_ids";
const _kQueueIndex = "playback_queue_index";

/// 播放状态机（§5.2-1：PlaySession + NextStrategy；引擎只做"取下一首→装载→播放"）
/// 断点续播：进度去抖 5s 写盘，暂停/切歌/销毁立即写（§5.2-2）
@Riverpod(keepAlive: true)
class Playback extends _$Playback implements SystemPlaybackCommands {
  AudioEngine? _engine;
  StreamSubscription? _onPosition;
  StreamSubscription? _onDuration;
  StreamSubscription? _onPlaying;
  StreamSubscription? _onCompletion;
  StreamSubscription? _onError;
  Timer? _persistDebounce;
  Timer? _sleepTimer;
  bool _restored = false;

  /// 引擎当前已装载的曲目 id（null = 引擎无源：冷启动恢复后/装载失败后）。
  /// 播放键据此决定裸 play 还是完整装载（裸 play 在无源引擎上无声无进度）
  String? _loadedKey;
  DateTime _lastSystemSync = DateTime.fromMillisecondsSinceEpoch(0);

  /// 惰性创建并订阅事件流（首次使用时；dispose 统一取消）
  AudioEngine _resolveEngine() {
    if (_engine != null) return _engine!;
    final e = playbackDepsTestOverride?.engine ?? JustAudioEngine();
    _engine = e;
    _subscribe(e);
    return e;
  }

  @override
  PlaybackState build() {
    ref.onDispose(_dispose);
    // 通知栏/耳机键命令接到本状态机（Android 才有 handler）
    playbackAudioHandler?.commands = this;
    _restoreFromPrefs();
    return const PlaybackState();
  }

  // ---- 系统媒体会话命令（通知栏/耳机键） ----

  @override
  Future<void> systemPlay() async {
    // 通知栏恢复播放与迷你条同链路（引擎无源时 toggle 会走完整装载续播）；
    // 仅在暂停态行动作，避免与 pause 语义打架
    if (!state.playing) await toggle();
  }

  @override
  Future<void> systemPause() => pause();

  @override
  Future<void> systemNext() => next();

  @override
  Future<void> systemPrevious() => previous();

  @override
  Future<void> systemSeek(Duration position) => seek(position);

  @override
  Future<void> systemStop() async {
    await _resolveEngine().stop();
    state = state.copyWith(playing: false, position: Duration.zero);
    _snapshot();
    _syncSystem(force: true);
  }

  /// 状态机 → 系统会话；position 高频更新按 1s 节流（通知栏自身会推算进度）
  void _syncSystem({bool force = false}) {
    final handler = playbackAudioHandler;
    if (handler == null) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastSystemSync) < const Duration(seconds: 1)) {
      return;
    }
    _lastSystemSync = now;
    handler.sync(
      SystemPlaybackSnapshot(
        track: state.track,
        playing: state.playing,
        buffering: state.buffering,
        position: state.position,
        duration: state.duration,
        mode: state.mode,
        queueIndex: state.queueIndex,
      ),
    );
  }

  /// 点播：以 [queue]（默认单曲）为会话队列播放 [track]
  Future<void> play(Track track, {List<Track>? queue}) async {
    // 切歌/换曲前先把旧曲进度写盘（§5.2-2：暂停/切歌立即写，不等 5s 去抖）
    _persistNow();
    var sessionQueue = (queue == null || queue.isEmpty) ? [track] : queue;
    var index = sessionQueue.indexWhere((t) => t.id == track.id);
    // 传入列表不含点播曲时退回单曲，避免误播列表首曲
    if (index < 0) {
      sessionQueue = [track];
      index = 0;
    }
    await _load(sessionQueue, index, autoplay: true);
  }

  Future<void> toggle() async {
    if (state.track == null) {
      // 无当前曲时从播放队列取第一首开播（插队队列优先，§3.4-5）
      final queued = await _takeQueuedTrack();
      if (queued != null) {
        ref.invalidate(queueTracksProvider);
        await _load([queued], 0, autoplay: true);
      }
      return;
    }
    if (state.playing) {
      // 乐观落定先行：暂停键必须即时响应（引擎异常/事件缺失也不能卡死）；
      // 引擎若实际未暂停，playingStream 会把状态校正回来
      state = state.copyWith(playing: false);
      _snapshot();
      _persistNow();
      _syncSystem();
      try {
        await _resolveEngine().pause();
      } catch (e) {
        print("暂停引擎失败：$e");
      }
      return;
    }
    // 引擎里没有当前曲（冷启动恢复不装载引擎/装载失败回退后）：裸 play()
    // 无声无进度、按钮永久卡死（真机反馈），必须走完整装载从展示进度续播
    if (_loadedKey != state.track!.id) {
      final queue = state.queue.isEmpty ? [state.track!] : state.queue;
      final index = state.queueIndex >= 0 ? state.queueIndex : 0;
      await _load(queue, index, autoplay: true, initialPosition: state.position);
      return;
    }
    // 乐观落定先行（同暂停）：引擎 no-op 无事件时 UI 也必须翻到暂停图标
    state = state.copyWith(playing: true);
    _syncSystem();
    try {
      await _resolveEngine().play();
    } catch (e) {
      print("恢复播放失败：$e");
      state = state.copyWith(playing: false);
    }
  }

  Future<void> pause() async {
    if (!state.playing) return;
    // 乐观落定先行（同 toggle 暂停分支）
    state = state.copyWith(playing: false);
    _snapshot();
    _persistNow();
    _syncSystem();
    try {
      await _resolveEngine().pause();
    } catch (e) {
      print("暂停引擎失败：$e");
    }
  }

  Future<void> seek(Duration position) async {
    await _resolveEngine().seek(position);
    state = state.copyWith(position: position);
    _snapshot();
    _persistDebounced();
    _syncSystem(force: true);
  }

  /// 循环切换播放模式（UI toast 文案取 label）
  Future<void> cycleMode() async {
    state = state.copyWith(mode: state.mode.next);
    _snapshot();
    appPrefs.setString(_kMode, state.mode.name);
    _syncSystem(force: true);
  }

  Future<void> next() => _jump(auto: false, backward: false);

  Future<void> previous() => _jump(auto: false, backward: true);

  /// 播完自动切歌的入口（completion 事件触发）
  /// 「播完再停」开启时停在当前曲，不进入下一首（定时关闭）
  Future<void> _onCompleted() async {
    if (state.stopAfterTrack) {
      _sleepTimer?.cancel();
      _sleepTimer = null;
      await _resolveEngine().stop();
      state = state.copyWith(
        playing: false,
        position: Duration.zero,
        clearSleep: true,
        stopAfterTrack: false,
      );
      _snapshot();
      _syncSystem(force: true);
      return;
    }
    await _jump(auto: true, backward: false);
  }

  /// 定时关闭：到点暂停（仅本会话有效，不持久化）
  void setSleepAfter(Duration duration) {
    _sleepTimer?.cancel();
    final deadline = DateTime.now().add(duration);
    state = state.copyWith(sleepDeadline: deadline, stopAfterTrack: false);
    _sleepTimer = Timer(duration, () async {
      _sleepTimer = null;
      if (state.track != null) {
        await _resolveEngine().pause();
        _persistNow();
        state = state.copyWith(
          playing: false,
          clearSleep: true,
          stopAfterTrack: false,
        );
      }
    });
  }

  /// 定时关闭：播完当前曲再停
  void setStopAfterCurrent() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(clearSleep: true, stopAfterTrack: true);
  }

  void cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(clearSleep: true, stopAfterTrack: false);
  }

  /// 清除错误态（全局提示已展示后调用，避免同一错误重复 toast）
  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  Future<void> _jump({required bool auto, required bool backward}) async {
    _persistNow();
    // 「下一首播放」插队优先：手动下一首与播完自动切歌都先消费队列表首曲
    if (!backward) {
      final queued = await _takeQueuedTrack();
      if (!ref.mounted) return;
      if (queued != null) {
        final session = [...state.queue];
        final insertAt = state.queueIndex < 0 ? 0 : state.queueIndex + 1;
        session.insert(insertAt, queued);
        // 队列表已消费一条，待播放分区（播放队列 sheet）即时刷新
        ref.invalidate(queueTracksProvider);
        await _load(session, insertAt, autoplay: true);
        return;
      }
    }
    final queue = state.queue;
    final target = nextIndex(
      mode: state.mode,
      current: state.queueIndex,
      queueLength: queue.length,
      auto: auto,
      backward: backward,
      randomPick: playbackDepsTestOverride?.randomPick,
    );
    if (target == null) {
      // 顺序模式到队尾（或队列空）：自然停止
      await _resolveEngine().stop();
      state = state.copyWith(playing: false, position: Duration.zero);
      _snapshot();
      _syncSystem(force: true);
      return;
    }
    await _load(queue, target, autoplay: true);
  }

  /// 从播放队列表取队首（事务内删除并顺移；失败不阻塞正常切歌）
  Future<Track?> _takeQueuedTrack() async {
    try {
      return await QueueRepository().takeFirst();
    } catch (e) {
      print("读取播放队列失败：$e");
      return null;
    }
  }

  /// 播放历史：曲目先确保入库（外键约束），同一曲目只保留最新一条。
  /// 返回 (recorded, previousMs)：recorded=是否成功写入；
  /// previousMs=写入前的旧时间戳，装载失败时用它回滚（失败播放不留「最近播放」）
  Future<({bool recorded, int? previousMs})> _recordHistory(Track track) async {
    try {
      await TrackRepository().upsert(track);
      final previousMs = await HistoryRepository().record(track.id);
      return (recorded: true, previousMs: previousMs);
    } catch (e) {
      print("记录播放历史失败：$e");
      return (recorded: false, previousMs: null);
    }
  }

  Future<void> _load(
    List<Track> queue,
    int index, {
    required bool autoplay,
    Duration? initialPosition,
  }) async {
    final track = queue[index];
    // 记住旧会话：装载失败时整态回退（曲目/队列/进度），
    // 不能让"点了但没播出来"的曲占住播放条/播放卡（真机反馈的严重问题）
    final prev = state;
    // 先记录历史再切 state：歌单页监听 track 变化后立即查询也能拿到最新记录；
    // 记下旧时间戳，装载失败时回滚，失败播放不留「最近播放」
    final history = await _recordHistory(track);
    if (!ref.mounted) return;
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
    _syncSystem(force: true);
    // resolveSource 失败时引擎未被动过，旧曲仍在播；一旦进入 load 阶段，
    // just_audio 会先停掉旧源——失败后引擎已哑，回退不能宣称仍在播
    var reachedEngine = false;
    try {
      final source = await _resolveSource(track);
      if (!ref.mounted) return;
      reachedEngine = true;
      await _resolveEngine().load(source, initialPosition: initialPosition);
      if (!ref.mounted) return;
      if (autoplay) await _resolveEngine().play();
      if (!ref.mounted) return;
      // 同一引擎切源时 playingStream 不一定会再次发 true（自动下一曲常见），
      // 只等 playing 事件清 buffering 会让 position 流被永久丢弃，进度条/歌词停在旧位置；
      // playing 同步乐观写，防止 UI 停在旧值
      state = state.copyWith(
        buffering: false,
        playing: autoplay ? true : state.playing,
      );
      _loadedKey = track.id;
      // 切歌后立即写新曲与队列快照：与 queue 表 takeFirst 的删除时序对齐，
      // 避免播放器启动后、下个去抖周期前被杀导致“已出队但快照仍是旧曲”
      _persistNow();
    } catch (e) {
      // 回滚乐观写入的播放历史（recorded=false 时没写过，无需回滚）
      if (history.recorded) {
        try {
          await HistoryRepository().restore(track.id, history.previousMs);
        } catch (err) {
          print("回滚播放历史失败：$err");
        }
      }
      // 引擎阶段失败 = 旧源已被打断，引擎无源；标记后下次播放走完整装载恢复
      _loadedKey = null;
      if (!ref.mounted) return;
      // 装载失败：类型化错误上抛到 state（UI 提示），不静默挂死（§5.1-2）
      print("播放装载失败 [${track.id}] $e");
      // B 站 -404（"啥都木有"）= 视频/分 P 已被删除或下架，翻译成用户能懂的提示
      final friendly = e is BiliApiRejectError && e.code == -404
          ? "原视频可能已丢失（被删除或下架），换首试试吧"
          : "$e";
      // 整态回退到旧会话（旧曲/队列/进度），错误挂上去 toast；
      // 引擎未被动过（源解析失败）→ 旧曲仍在播，保留播放态与听感一致；
      // 引擎已被动过（load 阶段失败）→ 强制暂停态，播放键走完整装载恢复
      state = prev.copyWith(
        buffering: false,
        error: friendly,
        playing: reachedEngine ? false : prev.playing,
      );
      _snapshot();
      _persistNow();
      _syncSystem(force: true);
    }
  }

  /// 源解析：本地文件（本地曲/已下载）优先直读；在线曲按音源取 playurl
  Future<PlaySource> _resolveSource(Track track) async {
    final override = playbackDepsTestOverride?.resolveSource;
    if (override != null) return override(track);
    var localPath = track.localPath;
    // 列表可能持旧 Track（下载前对象无 localPath）：回库补查，保证离线可播
    if (localPath == null || localPath.isEmpty) {
      try {
        final stored = await TrackRepository().getById(track.id);
        localPath = stored?.localPath;
      } catch (_) {
        // 查库失败按在线处理
      }
    }
    if (localPath != null && localPath.isNotEmpty) {
      try {
        if (File(localPath).existsSync()) {
          // §3.4-8：同身份离线——下载后的在线曲也走本地文件
          return PlaySource(key: track.id, url: localPath, isLocal: true);
        }
      } catch (_) {
        // 路径不可读时回退在线取流
      }
    }
    if (track.origin == OriginType.local) {
      throw StateError("本地文件不存在（可能已被移动或删除）");
    }
    if (track.origin == OriginType.kuwo) {
      final musicUrl = await kuwoApi.getMusicUrl(track.id);
      return PlaySource(
        key: track.id,
        url: musicUrl.url,
        backupUrl: musicUrl.backupUrl,
        headers: musicUrl.headers,
        contentType: musicUrl.contentType,
      );
    }
    if (track.origin == OriginType.netease) {
      final musicUrl = await neteaseApi.getMusicUrl(track.id);
      return PlaySource(
        key: track.id,
        url: musicUrl.url,
        backupUrl: musicUrl.backupUrl,
        headers: musicUrl.headers,
        contentType: musicUrl.contentType,
      );
    }
    if (track.origin == OriginType.qq) {
      final musicUrl = await qqApi.getMusicUrl(track.id);
      return PlaySource(
        key: track.id,
        url: musicUrl.url,
        backupUrl: musicUrl.backupUrl,
        headers: musicUrl.headers,
        contentType: musicUrl.contentType,
      );
    }
    if (track.origin == OriginType.qianqian) {
      final musicUrl = await qianqianApi.getMusicUrl(track.id);
      return PlaySource(
        key: track.id,
        url: musicUrl.url,
        backupUrl: musicUrl.backupUrl,
        headers: musicUrl.headers,
        contentType: musicUrl.contentType,
      );
    }
    final musicUrl = await biliApi.getMusicUrl(track.id);
    return PlaySource(
      key: track.id,
      url: musicUrl.url,
      backupUrl: musicUrl.backupUrl,
      headers: musicUrl.headers,
      contentType: musicUrl.contentType,
    );
  }

  void _subscribe(AudioEngine e) {
    _onPosition = e.positionStream.listen(
      (p) {
        if (!state.buffering) state = state.copyWith(position: p);
        _snapshot();
        _persistDebounced();
        _syncSystem();
      },
    );
    _onDuration = e.durationStream.listen((d) {
      state = state.copyWith(duration: d);
      _syncSystem(force: true);
    });
    _onPlaying = e.playingStream.listen((playing) {
      state = state.copyWith(playing: playing, buffering: false);
      _syncSystem(force: true);
    });
    _onCompletion = e.completionStream.listen((_) => unawaited(_onCompleted()));
    _onError = e.errorStream.listen((err) {
      print("播放引擎错误：$err");
      state = state.copyWith(
        buffering: false,
        playing: false,
        error: "$err",
      );
      _snapshot();
      _syncSystem(force: true);
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
  List<Track> _snapQueue = const [];
  int _snapQueueIndex = -1;

  void _snapshot() {
    if (state.track != null) _snapTrack = state.track;
    _snapPosition = state.position;
    _snapMode = state.mode;
    _snapQueue = state.queue;
    _snapQueueIndex = state.queueIndex;
  }

  void _persistNow() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    final track = _snapTrack;
    if (track == null) return;
    appPrefs.setString(_kTrackId, track.id);
    appPrefs.setInt(_kPositionMs, _snapPosition.inMilliseconds);
    appPrefs.setString(_kMode, _snapMode.name);
    // 队列快照与曲目同刻写入，保证恢复时 (track, queue, index) 三元一致
    appPrefs.setString(
      _kQueueIds,
      jsonEncode([for (final t in _snapQueue) t.id]),
    );
    appPrefs.setInt(_kQueueIndex, _snapQueueIndex);
  }

  /// 冷启动断点恢复：曲目/进度/模式 + 会话队列快照回填（暂停态；点播放续播）。
  /// 队列快照只存 id，回库重建；已删除曲目自动剔除，当前曲不在快照中则退回单曲。
  /// 插队/稍后听走 queue 表（自身跨启动持久），由 takeFirst 消费，无需在此恢复。
  Future<void> _restoreFromPrefs() async {
    if (_restored) return;
    _restored = true;
    final trackId = appPrefs.getString(_kTrackId);
    if (trackId == null) return;
    final modeName = appPrefs.getString(_kMode);
    final positionMs = appPrefs.getInt(_kPositionMs) ?? 0;
    final track = await TrackRepository().getById(trackId);
    if (!ref.mounted) return;
    if (track == null) return;
    var queue = <Track>[track];
    var index = 0;
    final idsJson = appPrefs.getString(_kQueueIds);
    if (idsJson != null) {
      try {
        final ids = (jsonDecode(idsJson) as List).cast<String>();
        final restored = await TrackRepository().getByIds(ids);
        var idx = restored.indexWhere((t) => t.id == trackId);
        // 队列允许重复曲目：优先用保存下标，其次按曲目 id 定位
        final savedIndex = appPrefs.getInt(_kQueueIndex) ?? -1;
        if (savedIndex >= 0 &&
            savedIndex < restored.length &&
            restored[savedIndex].id == trackId) {
          idx = savedIndex;
        }
        if (idx >= 0) {
          queue = restored;
          index = idx;
        }
      } catch (_) {
        // 快照损坏按单曲恢复
      }
    }
    state = state.copyWith(
      track: track,
      queue: queue,
      queueIndex: index,
      position: Duration(milliseconds: positionMs),
      mode: PlayMode.values
          .where((m) => m.name == modeName)
          .firstOrNull ?? PlayMode.listLoop,
    );
    _snapshot();
    _syncSystem(force: true);
  }

  void _dispose() {
    _persistNow();
    playbackAudioHandler?.detach();
    _onPosition?.cancel();
    _onDuration?.cancel();
    _onPlaying?.cancel();
    _onCompletion?.cancel();
    _onError?.cancel();
    _persistDebounce?.cancel();
    _sleepTimer?.cancel();
    // 释放底层播放器（AudioPlayer 持有平台解码器/网络连接）
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
  }
}
