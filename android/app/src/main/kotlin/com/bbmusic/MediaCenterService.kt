package com.bobomusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.widget.RemoteViews
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import java.util.concurrent.Executors

/**
 * 自研媒体中心：前台服务 + MediaSessionCompat + 自绘 RemoteViews 媒体通知。
 *
 * 通知走自绘是所有者的取舍：进度条与居中按钮在厂商媒体模板里拿不回来
 * （OriginOS 两态无进度条），只有 RemoteViews 能保证；代价是接受 ROM
 * 强插的图标列与系统头（见 layout/notification_media_center.xml 注释）。
 * 另：通知收起态只渲染收起槽位并按折叠高度裁剪——三行布局超高会被裁
 * （曾表现为只剩标题/歌手+半截进度线），收起槽位因此只放紧凑单行。
 *
 * 职责边界：音频播放完全在 Dart 侧（just_audio），本服务只做"系统展示与命令转达"——
 * 通知按钮/耳机键/锁屏/原子岛从这里读会话，命令经 MediaCenterBridge 送回 Dart 状态机。
 * 状态由 Dart 快照单向推入（sync），服务不持有播放逻辑。
 */
class MediaCenterService : Service() {

    companion object {
        private const val CHANNEL_ID = "com.bobomusic.channel.playback"
        private const val NOTIFICATION_ID = 0xB0B0
        private const val ACTION_PLAY = "com.bobomusic.media_center.PLAY"
        private const val ACTION_PAUSE = "com.bobomusic.media_center.PAUSE"
        private const val ACTION_NEXT = "com.bobomusic.media_center.NEXT"
        private const val ACTION_PREVIOUS = "com.bobomusic.media_center.PREVIOUS"
        private const val ACTION_STOP = "com.bobomusic.media_center.STOP"

        /** 服务实例（Dart 推状态用）；onCreate/onDestroy 维护 */
        @Volatile
        var instance: MediaCenterService? = null

        /** 服务未创建期间的待应用状态（startForegroundService 与 onCreate 竞态兜底） */
        @Volatile
        var pendingState: Map<String, Any?>? = null
    }

    private lateinit var session: MediaSessionCompat
    private lateinit var notificationManager: NotificationManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val coverExecutor = Executors.newSingleThreadExecutor()

    private var state: Map<String, Any?> = emptyMap()
    private var coverBitmap: Bitmap? = null

    /** 已解码封面对应的路径；null = 无封面（回退 App 图标） */
    private var decodedCoverPath: String? = null

    // 缓存的 RemoteViews 实例：复用实例让 SystemUI 走增量 reapply，每秒只刷新真正变化的进度，
    // 避免逐秒全量重设图标/文案在展开收起动画中产生闪烁；每 60 次增量后整体重建，防止动作列表无限增长
    private var compactViews: RemoteViews? = null
    private var expandedViews: RemoteViews? = null
    private var boundSignature: String? = null
    private var appliedPlaying: Boolean? = null
    private var appliedPositionMs = -1L
    private var rebuildTicks = 0

    /** 会话元数据签名：只随曲目/封面变化，防止逐秒原样重发导致系统媒体卡跟着重绘 */
    private var metadataSignature: String? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(NotificationManager::class.java)
        createChannel()
        session = MediaSessionCompat(this, "BoboMediaCenter").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = MediaCenterBridge.sendToDart("play")
                override fun onPause() = MediaCenterBridge.sendToDart("pause")
                override fun onSkipToNext() = MediaCenterBridge.sendToDart("next")
                override fun onSkipToPrevious() = MediaCenterBridge.sendToDart("previous")
                override fun onSeekTo(pos: Long) = MediaCenterBridge.sendToDart("seek", pos)
            })
        }
        session.isActive = true
        // 会话拉起入口：媒体卡/原子岛点按打开 App 的依据；缺失时部分 ROM 按紧凑形态渲染（audio_service 同款）
        session.setSessionActivity(launchPendingIntent())
        // startForegroundService 启动后必须立刻进前台态；内容随即由 applyState 刷新
        startForeground(NOTIFICATION_ID, buildNotification())
        pendingState?.let { applyState(it) }
        pendingState = null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 任何路径到达这里都先保证前台态（Android 12+ 后台 startForegroundService 约束）
        startForeground(NOTIFICATION_ID, buildNotification())
        when (intent?.action) {
            ACTION_PLAY -> MediaCenterBridge.sendToDart("play")
            ACTION_PAUSE -> MediaCenterBridge.sendToDart("pause")
            ACTION_NEXT -> MediaCenterBridge.sendToDart("next")
            ACTION_PREVIOUS -> MediaCenterBridge.sendToDart("previous")
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            Intent.ACTION_MEDIA_BUTTON -> MediaButtonReceiver.handleIntent(session, intent)
        }
        // 进程被杀不自动重建：引擎在 Dart 侧，重建只会得到一张空通知
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        session.isActive = false
        session.release()
        coverExecutor.shutdown()
        super.onDestroy()
    }

    /** Dart 快照入口（主线程调用）：刷新会话 + 通知 + 按需解码封面 */
    fun applyState(next: Map<String, Any?>) {
        state = next
        updateSessionPlaybackState()
        updateMetadata()
        refreshNotificationViews()
        notificationManager.notify(NOTIFICATION_ID, buildNotification())
        decodeCoverIfNeeded()
    }

    /** 刷新通知内容视图：没变化的槽位不加动作，SystemUI reapply 时保持原样不重绘 */
    private fun refreshNotificationViews() {
        val playing = state["playing"] as? Boolean ?: false
        val title = state["title"] as? String ?: "啵啵音乐"
        val artist = state["artist"] as? String ?: ""
        val durationMs = (state["durationMs"] as? Number)?.toLong() ?: 0L
        val positionMs = (state["positionMs"] as? Number)?.toLong() ?: 0L
        val signature = "$title|$artist|$durationMs"
        if (compactViews == null || expandedViews == null || signature != boundSignature ||
            appliedPlaying == null || rebuildTicks >= 60
        ) {
            val compact = RemoteViews(packageName, R.layout.notification_media_center_compact)
            val expanded = RemoteViews(packageName, R.layout.notification_media_center)
            bindCompactViews(compact)
            bindMediaViews(expanded)
            compactViews = compact
            expandedViews = expanded
            boundSignature = signature
            appliedPlaying = playing
            appliedPositionMs = positionMs
            rebuildTicks = 0
            return
        }
        rebuildTicks++
        if (playing != appliedPlaying) {
            val icon = if (playing) R.drawable.pause_circle else R.drawable.play_circle
            val toggle = actionPendingIntent(if (playing) ACTION_PAUSE else ACTION_PLAY, 2)
            for (views in listOfNotNull(compactViews, expandedViews)) {
                views.setImageViewResource(R.id.notification_action_toggle, icon)
                views.setOnClickPendingIntent(R.id.notification_action_toggle, toggle)
            }
            appliedPlaying = playing
        }
        if (positionMs != appliedPositionMs) {
            val safeDuration = durationMs.coerceAtLeast(1L)
            expandedViews?.setProgressBar(
                R.id.notification_progress,
                safeDuration.toInt(),
                positionMs.coerceIn(0L, safeDuration).toInt(),
                false,
            )
            expandedViews?.setTextViewText(R.id.notification_time_elapsed, formatTime(positionMs))
            expandedViews?.setTextViewText(R.id.notification_time_total, formatTime(durationMs))
            appliedPositionMs = positionMs
        }
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "播放状态",
            NotificationManager.IMPORTANCE_LOW,
        ).apply { description = "啵啵音乐播放控制" }
        notificationManager.createNotificationChannel(channel)
    }

    private fun updateSessionPlaybackState() {
        val playing = state["playing"] as? Boolean ?: false
        val buffering = state["buffering"] as? Boolean ?: false
        val positionMs = (state["positionMs"] as? Number)?.toLong() ?: 0L
        val speed = (state["speed"] as? Number)?.toFloat() ?: 1f
        val playbackState = when {
            buffering -> PlaybackStateCompat.STATE_BUFFERING
            playing -> PlaybackStateCompat.STATE_PLAYING
            else -> PlaybackStateCompat.STATE_PAUSED
        }
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY
                        or PlaybackStateCompat.ACTION_PAUSE
                        or PlaybackStateCompat.ACTION_PLAY_PAUSE
                        or PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                        or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                        or PlaybackStateCompat.ACTION_SEEK_TO
                        or PlaybackStateCompat.ACTION_STOP,
                )
                .setState(playbackState, positionMs, if (playing) speed else 0f, SystemClock.elapsedRealtime())
                .build(),
        )
    }

    private fun updateMetadata() {
        val title = state["title"] as? String ?: ""
        val artist = state["artist"] as? String ?: ""
        val durationMs = (state["durationMs"] as? Number)?.toLong() ?: 0L
        val signature = "$title|$artist|$durationMs|${coverBitmap != null}"
        if (signature == metadataSignature) return
        metadataSignature = signature
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, state["title"] as? String ?: "")
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, state["artist"] as? String ?: "")
            .putLong(
                MediaMetadataCompat.METADATA_KEY_DURATION,
                (state["durationMs"] as? Number)?.toLong() ?: 0L,
            )
        coverBitmap?.let { metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) }
        session.setMetadata(metadata.build())
    }

    private fun buildNotification(): Notification {
        val playing = state["playing"] as? Boolean ?: false
        val contentIntent = launchPendingIntent()
        val deleteIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, MediaCenterService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // 正常路径 applyState 已先建好缓存实例；此处兜底防未初始化路径
        val compact = compactViews
            ?: RemoteViews(packageName, R.layout.notification_media_center_compact)
                .also { bindCompactViews(it) }
        val expanded = expandedViews
            ?: RemoteViews(packageName, R.layout.notification_media_center)
                .also { bindMediaViews(it) }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setCustomContentView(compact)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        return builder.build()
    }

    /** 紧凑行绑定：文案/播放态图标/播放暂停点击（控件 id 与展开布局同名） */
    private fun bindCompactViews(content: RemoteViews) {
        val playing = state["playing"] as? Boolean ?: false
        content.setTextViewText(R.id.notification_title, state["title"] as? String ?: "啵啵音乐")
        content.setTextViewText(R.id.notification_artist, state["artist"] as? String ?: "")
        content.setImageViewResource(
            R.id.notification_action_toggle,
            if (playing) R.drawable.pause_circle else R.drawable.play_circle,
        )
        content.setOnClickPendingIntent(
            R.id.notification_action_toggle,
            actionPendingIntent(if (playing) ACTION_PAUSE else ACTION_PLAY, 2),
        )
    }

    /** 三行展开卡绑定：文案/进度/时间/播放态图标/三按钮点击 */
    private fun bindMediaViews(content: RemoteViews) {
        val playing = state["playing"] as? Boolean ?: false
        content.setTextViewText(R.id.notification_title, state["title"] as? String ?: "啵啵音乐")
        content.setTextViewText(R.id.notification_artist, state["artist"] as? String ?: "")
        val durationMs = (state["durationMs"] as? Number)?.toLong() ?: 0L
        val positionMs = (state["positionMs"] as? Number)?.toLong() ?: 0L
        val safeDuration = durationMs.coerceAtLeast(1L)
        content.setProgressBar(
            R.id.notification_progress,
            safeDuration.toInt(),
            positionMs.coerceIn(0L, safeDuration).toInt(),
            false,
        )
        content.setTextViewText(R.id.notification_time_elapsed, formatTime(positionMs))
        content.setTextViewText(R.id.notification_time_total, formatTime(durationMs))
        content.setImageViewResource(
            R.id.notification_action_toggle,
            if (playing) R.drawable.pause_circle else R.drawable.play_circle,
        )
        content.setOnClickPendingIntent(
            R.id.notification_action_previous,
            actionPendingIntent(ACTION_PREVIOUS, 1),
        )
        content.setOnClickPendingIntent(
            R.id.notification_action_toggle,
            actionPendingIntent(if (playing) ACTION_PAUSE else ACTION_PLAY, 2),
        )
        content.setOnClickPendingIntent(
            R.id.notification_action_next,
            actionPendingIntent(ACTION_NEXT, 3),
        )
    }

    /** 毫秒 → m:ss（进度行时间标签） */
    private fun formatTime(ms: Long): String {
        val totalSeconds = ms.coerceAtLeast(0L) / 1000
        return "${totalSeconds / 60}:${(totalSeconds % 60).toString().padStart(2, '0')}"
    }

    private fun actionPendingIntent(action: String, requestCode: Int): PendingIntent =
        PendingIntent.getService(
            this,
            requestCode,
            Intent(this, MediaCenterService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** 通知与媒体会话共用的拉起入口（同 requestCode/Intent 由系统去重为同一条 PendingIntent） */
    private fun launchPendingIntent(): PendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** 封面路径变化才重新解码；解码在后台线程，完成后回主线程刷新 */
    private fun decodeCoverIfNeeded() {
        val path = state["coverPath"] as? String
        if (path == decodedCoverPath) return
        decodedCoverPath = path
        coverBitmap = null
        if (path == null) {
            updateMetadata()
            notificationManager.notify(NOTIFICATION_ID, buildNotification())
            return
        }
        coverExecutor.execute {
            val bitmap = decodeScaledBitmap(path)
            if (bitmap != null) {
                coverBitmap = bitmap
            } else {
                // 解码失败原本是静默的，封面排障需要这行日志与 Dart 侧拉取失败日志配对
                Log.w("MediaCenter", "封面解码失败：$path")
            }
            mainHandler.post {
                if (decodedCoverPath == path && instance != null) {
                    updateMetadata()
                    notificationManager.notify(NOTIFICATION_ID, buildNotification())
                }
            }
        }
    }

    /** 长边压到 512px 解码，避免原始封面占满内存 */
    private fun decodeScaledBitmap(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= 512 || bounds.outHeight / (sample * 2) >= 512) {
            sample *= 2
        }
        return BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }
}
