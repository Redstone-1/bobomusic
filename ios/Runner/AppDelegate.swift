import Flutter
import UIKit
import MediaPlayer

/// Dart 与 iOS 系统媒体中心（锁屏/控制中心/线控）之间的通道桥。
///
/// 协议与 Android 侧 MediaCenterBridge 完全一致：下行 update/stop（载荷同 mediaStateMap），
/// 上行 play/pause/next/previous/seek。状态由 Dart 快照单向推入，本桥不持有播放逻辑；
/// 锁屏进度由系统按 ElapsedPlaybackTime+PlaybackRate 自行推算，无需逐秒重发。
class MediaCenterBridge: NSObject {

    /// App 生命周期单例：远控命令回调持弱引用，桥本身须常驻（AppDelegate 持有）
    static var shared: MediaCenterBridge?

    private let channel: FlutterMethodChannel
    private let center = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var title = ""
    private var artist = ""
    private var durationMs = 0
    private var positionMs = 0
    private var speed = 1.0
    private var playing = false

    /// 已加载封面路径：路径不变不重复解码（镜像 Android decodeCoverIfNeeded）
    private var loadedCoverPath: String?
    private var artwork: MPMediaItemArtwork?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "com.bobomusic/media_center", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "bridge_gone", message: "bridge released", details: nil))
                return
            }
            switch call.method {
            case "update":
                self.apply(arguments: call.arguments as? [String: Any])
                result(nil)
            case "stop":
                self.clear()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        registerCommands()
    }

    private func apply(arguments: [String: Any]?) {
        guard let args = arguments else { return }
        title = args["title"] as? String ?? ""
        artist = args["artist"] as? String ?? ""
        durationMs = (args["durationMs"] as? NSNumber)?.intValue ?? 0
        positionMs = (args["positionMs"] as? NSNumber)?.intValue ?? 0
        speed = (args["speed"] as? NSNumber)?.doubleValue ?? 1.0
        playing = args["playing"] as? Bool ?? false
        refreshNowPlaying()
        loadCoverIfNeeded(args["coverPath"] as? String)
    }

    private func refreshNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000.0,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        // 时长未就绪（0）时不下发，避免锁屏显示错误总长
        if durationMs > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        }
        if let artwork = artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
    }

    private func loadCoverIfNeeded(_ path: String?) {
        guard let path = path, path != loadedCoverPath else { return }
        loadedCoverPath = path
        // 文件 IO 放后台线程，解码完成后回主线程补一次正在播放信息
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = path.isEmpty ? nil : UIImage(contentsOfFile: path)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let image = image else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.refreshNowPlaying()
            }
        }
    }

    private func clear() {
        title = ""
        artist = ""
        durationMs = 0
        positionMs = 0
        playing = false
        loadedCoverPath = nil
        artwork = nil
        center.nowPlayingInfo = nil
    }

    private func registerCommands() {
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.send("play")
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.send("pause")
            return .success
        }
        commandCenter.togglePlaybackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.send(self.playing ? "pause" : "play")
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.send("next")
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.send("previous")
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let e = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.send("seek", Int(e.positionTime * 1000))
            return .success
        }
    }

    /// 命令回投 Dart 状态机；远控事件可能在非主线程到达，通道调用必须回主线程
    private func send(_ method: String, _ argument: Any? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod(method, argument: argument)
        }
    }
}

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      MediaCenterBridge.shared = MediaCenterBridge(messenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
