package chat.csac.unour

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject
import java.net.HttpCookie
import java.net.URL
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection

/** Credentials live only in this process. No restarted worker or saved notification contains them. */
internal object LiveTableSession {
    var snapshot: TableState? = null
    var connection: JSONObject? = null
    var dismissed: String? = null
    var foreground = true
    var generation = 0
    var cookies = mutableMapOf<String, String>()
    @Volatile var request: HttpsURLConnection? = null

    fun stop(context: Context, clear: Boolean = false) {
        generation++
        request?.disconnect()
        request = null
        context.stopService(Intent(context, LiveTableService::class.java))
        if (clear) {
            snapshot = null
            connection = null
            cookies.clear()
        }
    }

    fun start(context: Context) {
        val current = snapshot ?: return
        if (foreground || current.key == dismissed || connection == null) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val intent = Intent(context, LiveTableService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        } catch (_: IllegalStateException) {
            // The OS may have already suspended the activity. Never bypass its FGS restrictions.
        } catch (_: SecurityException) {
            // A revoked permission must not interrupt the game itself.
        }
    }
}

class LiveTableService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val reader = Executors.newSingleThreadExecutor()
    private var failures = 0
    private var reading = false
    private var stopped = false
    private val poll = Runnable { readTable() }
    private val markStale = Runnable {
        if (!stopped && !LiveTableSession.foreground) {
            LiveTableSession.snapshot?.let { current ->
                if (System.currentTimeMillis() - current.updatedAt >= 15000) {
                    LiveTableSession.snapshot = current.disconnected()
                    getSystemService(NotificationManager::class.java).notify(ID, notification(current.disconnected()))
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            LiveTableSession.dismissed = LiveTableSession.snapshot?.key
            LiveTableSession.stop(this)
            return START_NOT_STICKY
        }
        val snapshot = LiveTableSession.snapshot
        if (snapshot == null || LiveTableSession.foreground || LiveTableSession.connection == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        val notification = notification(snapshot)
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(ID, notification)
        } catch (_: RuntimeException) {
            stopSelf()
            return START_NOT_STICKY
        }
        handler.removeCallbacks(poll)
        scheduleStale(snapshot)
        if (!reading) handler.post(poll)
        return START_NOT_STICKY
    }

    private fun readTable() {
        if (stopped || LiveTableSession.foreground) return
        val configuration = LiveTableSession.connection ?: return
        val generation = LiveTableSession.generation
        reading = true
        reader.execute {
            var next: TableState? = null
            var terminal = false
            var responseCookies = emptyList<String>()
            var request: HttpsURLConnection? = null
            try {
                val url = URL(configuration.getString("url"))
                require(url.protocol == "https")
                request = url.openConnection() as HttpsURLConnection
                LiveTableSession.request = request
                request.instanceFollowRedirects = false
                request.connectTimeout = 12000
                request.readTimeout = 18000
                request.setRequestProperty("Accept", "application/json")
                request.setRequestProperty("Authorization", "Bearer ${configuration.getString("token")}")
                request.setRequestProperty("X-Account-ID", configuration.optString("accountId"))
                request.setRequestProperty("Cookie", configuration.optString("cookie"))
                when (request.responseCode) {
                    200 -> {
                        val room = request.inputStream.bufferedReader().use { JSONObject(it.readText()) }
                        next = TableState.fromRoom(room)
                        require(next.roomId == LiveTableSession.snapshot?.roomId)
                        terminal = next.phase == "finished"
                        responseCookies = request.headerFields.entries
                            .filter { it.key.equals("set-cookie", ignoreCase = true) }
                            .flatMap { it.value ?: emptyList() }
                    }
                    401, 403, 404 -> terminal = true
                }
            } catch (_: Exception) {
                // Keep the last successful timestamp and clearly mark the snapshot disconnected.
            } finally {
                request?.disconnect()
                if (LiveTableSession.request === request) LiveTableSession.request = null
            }
            handler.post {
                reading = false
                if (stopped || generation != LiveTableSession.generation || LiveTableSession.foreground) return@post
                if (terminal) {
                    LiveTableSession.stop(this, clear = true)
                    return@post
                }
                if (next != null) {
                    failures = 0
                    LiveTableSession.snapshot = next
                    if (responseCookies.isNotEmpty()) mergeCookies(configuration, responseCookies)
                } else {
                    failures = (failures + 1).coerceAtMost(4)
                    LiveTableSession.snapshot = LiveTableSession.snapshot?.disconnected()
                }
                LiveTableSession.snapshot?.let { state ->
                    getSystemService(NotificationManager::class.java).notify(ID, notification(state))
                    scheduleStale(state)
                }
                handler.postDelayed(poll, if (failures == 0) 2000 else (2000L shl failures).coerceAtMost(30000))
            }
        }
    }

    private fun scheduleStale(state: TableState) {
        handler.removeCallbacks(markStale)
        if (state.connected) handler.postDelayed(markStale, (state.updatedAt + 15000 - System.currentTimeMillis()).coerceAtLeast(1))
    }

    private fun mergeCookies(configuration: JSONObject, headers: List<String>) {
        val values = configuration.optString("cookie").split("; ").mapNotNull {
            val pieces = it.split('=', limit = 2)
            if (pieces.size == 2) pieces[0] to pieces[1] else null
        }.toMap().toMutableMap()
        for (header in headers) {
            try {
                for (cookie in HttpCookie.parse(header)) {
                    if (cookie.hasExpired()) values.remove(cookie.name) else values[cookie.name] = cookie.value
                    LiveTableSession.cookies[cookie.name] = header
                }
            } catch (_: IllegalArgumentException) { }
        }
        configuration.put("cookie", values.entries.joinToString("; ") { "${it.key}=${it.value}" })
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "后台牌桌", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "正在参与的 Unour 牌桌"
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun notification(state: TableState): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("liveRoomId", state.roomId)
            putExtra("liveSpectator", state.spectator)
        }
        val content = PendingIntent.getActivity(this, ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, ID + 1, Intent(this, LiveTableService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(state.updatedAt))
        val direction = if (state.data.optInt("direction", 1) == 1) "顺时针" else "逆时针"
        val text = "${state.summary}\n${state.data.optString("players")}\n$direction · 最近同步 $time${if (state.connected) "" else " · 连接中断"}"
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_live_table)
            .setContentTitle("${state.turn} · Unour")
            .setContentText(state.summary)
            .setSubText("牌桌 ${state.roomId} · 第 ${state.round} 局")
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setColor(Color.rgb(114, 80, 202))
            .setWhen(state.updatedAt)
            .setShowWhen(true)
            .setContentIntent(content)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(Notification.Action.Builder(null, "停止显示", stop).build())
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        if (Build.VERSION.SDK_INT >= 36) {
            builder.setShortCriticalText(if (!state.connected) "待刷新" else if (state.yourTurn) "轮到你" else state.data.optString("symbol"))
            try {
                // New Android 16 releases expose the explicit promotion request.
                builder.javaClass.getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType).invoke(builder, true)
            } catch (_: ReflectiveOperationException) {
                // The original API 36 SDK uses colorized ongoing standard templates.
                builder.setColorized(true)
            }
        }
        return builder.build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        LiveTableSession.stop(this, clear = true)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        LiveTableSession.stop(this, clear = true)
    }

    override fun onDestroy() {
        stopped = true
        handler.removeCallbacksAndMessages(null)
        LiveTableSession.request?.disconnect()
        LiveTableSession.request = null
        reader.shutdownNow()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "unour_live_table"
        const val ID = 2026
        const val STOP = "chat.csac.unour.STOP_LIVE_TABLE"
    }
}
