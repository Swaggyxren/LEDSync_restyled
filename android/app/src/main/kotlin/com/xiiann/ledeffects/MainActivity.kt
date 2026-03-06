package com.xiiann.ledsync

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CH = "ledsync/notif_listener"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> {
                    result.success(isNotificationListenerEnabled())
                }
                "openSettings" -> {
                    openNotificationListenerSettings()
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
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        if (flat.isEmpty()) return false

        val names = flat.split(":")
        for (n in names) {
            // entries look like: com.xiiann.ledeffects/com.xiiann.ledeffects.NotificationLedService
            if (n.startsWith(pkgName)) return true
        }
        return false
    }
}
