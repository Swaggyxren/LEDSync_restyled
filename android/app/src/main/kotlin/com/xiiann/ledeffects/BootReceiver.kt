package com.xiiann.ledsync

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.util.Log

/**
 * Requests the system to rebind [NotificationLedService] after:
 *  - Device boot (ACTION_BOOT_COMPLETED)
 *  - App update / reinstall (MY_PACKAGE_REPLACED)
 *
 * NotificationListenerService is system-managed so we can't start it
 * directly — requestRebind() tells the OS to reconnect it.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            Log.d("NotifLED", "BootReceiver: requesting service rebind (${intent.action})")
            NotificationListenerService.requestRebind(
                ComponentName(context, NotificationLedService::class.java)
            )
        }
    }
}