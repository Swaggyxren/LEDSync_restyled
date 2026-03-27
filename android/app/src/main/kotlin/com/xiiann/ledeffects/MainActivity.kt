package com.xiiann.ledsync

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CH = "ledsync/notif_listener"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "isEnabled" ->
                        result.success(isNotificationListenerEnabled())

                    "openSettings" -> {
                        openNotificationListenerSettings()
                        result.success(null)
                    }

                    // Android 13+ (API 33) requires POST_NOTIFICATIONS at runtime
                    // for any notification — including the foreground service one.
                    "hasPostNotifications" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                                    PackageManager.PERMISSION_GRANTED
                        } else true // auto-granted below API 33
                        result.success(granted)
                    }

                    "requestPostNotifications" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQUEST_POST_NOTIF
                            )
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationListenerSettings() {
        val i = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(i)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        if (flat.isEmpty()) return false
        return flat.split(":").any { it.startsWith(packageName) }
    }

    companion object {
        private const val REQUEST_POST_NOTIF = 1001
    }
}