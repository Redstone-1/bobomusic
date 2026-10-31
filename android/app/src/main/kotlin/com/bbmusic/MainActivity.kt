package com.bobomusic

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Dart 与媒体中心服务之间的通道桥。
 *
 * 方向一（Dart → 原生）：update/stop，驱动服务与通知。
 * 方向二（原生 → Dart）：服务把通知按钮/耳机键/锁屏命令送回 Dart 状态机。
 */
object MediaCenterBridge {
    private const val CHANNEL_NAME = "com.bobomusic/media_center"

    @Volatile
    var channel: MethodChannel? = null

    @Volatile
    lateinit var appContext: Context
        private set

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Activity 创建引擎时调用；appContext 用应用级上下文，服务启停不依赖 Activity 存活 */
    fun attach(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL_NAME).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        val state = call.arguments as? Map<String, Any?>
                        startOrUpdate(state ?: emptyMap())
                        result.success(null)
                    }
                    "stop" -> {
                        appContext.stopService(Intent(appContext, MediaCenterService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** 服务在跑就原地刷状态；没跑则携带初始状态拉起前台服务 */
    fun startOrUpdate(state: Map<String, Any?>) {
        MediaCenterService.pendingState = state
        val service = MediaCenterService.instance
        if (service != null) {
            service.applyState(state)
        } else {
            appContext.startForegroundService(Intent(appContext, MediaCenterService::class.java))
        }
    }

    /** 服务 → Dart：通知按钮/耳机键/锁屏命令 */
    fun sendToDart(method: String, argument: Any? = null) {
        mainHandler.post {
            try {
                channel?.invokeMethod(method, argument)
            } catch (_: IllegalStateException) {
                // 引擎已随 Activity 销毁（极端场景），命令无处投递，静默丢弃
            }
        }
    }
}

class MainActivity : FlutterActivity() {

    companion object {
        /** 引擎常驻引用：后台播放时 Activity 可能销毁，静态引用阻止引擎回收（audio_service 同款思路） */
        @Volatile
        private var cachedEngine: FlutterEngine? = null
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        if (cachedEngine == null) {
            cachedEngine = FlutterEngineGroup(this).createAndRunDefaultEngine(this)
        }
        return cachedEngine
    }

    // 引擎保活依赖 provideFlutterEngine 的静态缓存（audio_service 同款做法，
    // 其 AudioServiceActivity 也只覆盖此方法）；不再覆盖 shouldDestroyEngineWithEnd，
    // 该方法在本 Flutter 版本已移除，默认行为不销毁外部提供的引擎

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaCenterBridge.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
