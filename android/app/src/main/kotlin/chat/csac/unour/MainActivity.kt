package chat.csac.unour

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private var ready = false
    private var activityForeground = false

    private fun allowed(): Boolean =
        getSystemService(NotificationManager::class.java).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    private fun pendingOpen(): Map<String, Any>? {
        val id = intent?.getStringExtra("liveRoomId") ?: return null
        intent.removeExtra("liveRoomId")
        return mapOf("roomId" to id, "spectator" to intent.getBooleanExtra("liveSpectator", false))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chat.csac.unour/live_table").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        ready = true
                        result.success(mapOf(
                        "supported" to true,
                        "allowed" to allowed(),
                        "realtime" to true,
                        "platform" to "android",
                        "openTable" to pendingOpen(),
                        ))
                    }
                    "requestPermission" -> {
                        LiveTableSession.dismissed = null
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) result.error("busy", "Notification permission is already being requested", null)
                            else {
                                permissionResult = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2026)
                            }
                        } else result.success(allowed())
                    }
                    "sync" -> {
                        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val snapshot = TableState(JSONObject(arguments["snapshot"] as Map<*, *>))
                        val connection = JSONObject(arguments["connection"] as Map<*, *>)
                        if (LiveTableSession.snapshot?.roomId != snapshot.roomId) {
                            LiveTableSession.stop(this@MainActivity, clear = true)
                            LiveTableSession.dismissed = null
                        }
                        val current = LiveTableSession.snapshot
                        if (current == null || current.roomId != snapshot.roomId ||
                            (snapshot.data.optInt("revision") >= current.data.optInt("revision") &&
                                snapshot.data.optInt("version") >= current.data.optInt("version"))) {
                            LiveTableSession.snapshot = snapshot
                        }
                        if (!LiveTableSession.foreground && LiveTableSession.cookies.isNotEmpty()) {
                            connection.put("cookie", LiveTableSession.connection?.optString("cookie") ?: "")
                        }
                        LiveTableSession.connection = connection
                        LiveTableSession.foreground = activityForeground && arguments["foreground"] != false
                        if (!LiveTableSession.foreground) LiveTableSession.start(this@MainActivity)
                        result.success(null)
                    }
                    "foreground" -> {
                        val foreground = call.argument<Boolean>("value") != false
                        LiveTableSession.foreground = foreground && activityForeground
                        if (LiveTableSession.foreground) LiveTableSession.stop(this@MainActivity)
                        else LiveTableSession.start(this@MainActivity)
                        val cookies = if (foreground) LiveTableSession.cookies.values.toList() else emptyList()
                        if (foreground) LiveTableSession.cookies.clear()
                        result.success(mapOf("cookies" to cookies))
                    }
                    "stop" -> {
                        LiveTableSession.stop(this@MainActivity, clear = true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onPause() {
        activityForeground = false
        LiveTableSession.foreground = false
        LiveTableSession.start(this)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        activityForeground = true
        LiveTableSession.foreground = true
        LiveTableSession.stop(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (ready) pendingOpen()?.let { channel?.invokeMethod("openTable", it) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2026) {
            permissionResult?.success(allowed())
            permissionResult = null
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        permissionResult?.success(false)
        permissionResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
