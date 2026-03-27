package com.xiiann.ledsync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.DataOutputStream
import kotlin.concurrent.thread

class NotificationLedService : NotificationListenerService() {

    // ── Hardware paths ────────────────────────────────────────────────────────
    private val LB_CMD_PATH  = "/sys/led/led/tran_led_cmd"
    private val HWEN_PATH    = "/sys/class/leds/aw22xxx_led/hwen"
    private val BRIGHT_PATH  = "/sys/class/leds/aw22xxx_led/brightness"

    // ── Timing ────────────────────────────────────────────────────────────────
    private val SEQUENCE_COOLDOWN_MS = 6000L  // covers both writes + margin
    private val DOUBLE_FIRE_DELAY_MS = 1500L  // gap between write 1 and write 2
    private val LOOP_AUTO_STOP_MS    = 5000L  // looping pattern max on-time

    // ── State ─────────────────────────────────────────────────────────────────
    // Per-package last-trigger time for non-looping (one-shot × 5) patterns.
    private val lastTriggerPerPkg = HashMap<String, Long>()
    // Packages currently running a looping pattern — prevents re-fire.
    private val activeLoopingPkgs = mutableSetOf<String>()

    // ── System services ───────────────────────────────────────────────────────
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var powerManager: PowerManager
    private lateinit var notifManager: NotificationManager

    private val CHANNEL_ID = "ledsync_service"
    private val FG_NOTIF_ID = 101

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        powerManager  = getSystemService(PowerManager::class.java)
        notifManager  = getSystemService(NotificationManager::class.java)
        createNotificationChannel()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d("NotifLED", "Listener CONNECTED ✅")
        // Start foreground to prevent OEM battery managers from killing us.
        // ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC = 0x00000001
        startForeground(FG_NOTIF_ID, buildNotification(), 0x00000001)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d("NotifLED", "Listener DISCONNECTED ❌ — requesting rebind")
        // Ask the system to reconnect us automatically.
        requestRebind(ComponentName(this, NotificationLedService::class.java))
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    // ── Foreground notification ───────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "LED Sync Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps LED effects running in the background"
            setShowBadge(false)
        }
        notifManager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("LED Sync")
            .setContentText("Listening for notifications")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    // ── Root helpers ──────────────────────────────────────────────────────────

    private fun runSu(cmd: String): Boolean {
        return try {
            val p = Runtime.getRuntime().exec("su")
            DataOutputStream(p.outputStream).use { os ->
                os.writeBytes("$cmd\n")
                os.writeBytes("exit\n")
                os.flush()
            }
            p.waitFor()
            p.exitValue() == 0
        } catch (t: Throwable) {
            Log.e("NotifLED", "su exec failed: $cmd", t)
            false
        }
    }

    /**
     * Single su call: enable hardware + reset controller + write effect hex.
     * Previously two separate runSu calls had a timing gap that caused
     * the effect write to be missed intermittently.
     */
    private fun fireEffect(hex: String, tag: String): Boolean {
        // Step 1: reset controller (must complete before effect write)
        runSu(
            "echo 1 > $HWEN_PATH; " +
            "echo c > /sys/class/leds/aw22xxx_led/imax 2>/dev/null || true; " +
            "echo 255 > $BRIGHT_PATH; " +
            "echo none > /sys/class/leds/aw22xxx_led/trigger 2>/dev/null || true; " +
            "echo -n '00 00 00 00 00 00' > $LB_CMD_PATH"
        )
        // Step 2: write effect hex
        val ok = runSu("echo -n '$hex' > $LB_CMD_PATH")
        Log.d("NotifLED", "$tag -> ok=$ok hex='$hex'")
        return ok
    }

    /** Stop command — no need to enable engine, just send the off hex. */
    private fun fireStop(hex: String, tag: String): Boolean {
        val ok = runSu("echo -n '$hex' > $LB_CMD_PATH")
        Log.d("NotifLED", "$tag -> ok=$ok hex='$hex'")
        return ok
    }

    /**
     * Flutter shared_preferences stores StringList as:
     *   VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!["pkg1","pkg2"]
     * The base64 prefix + "!" must be stripped before parsing as JSONArray.
     * getStringSet() crashes (ClassCastException), direct JSONArray parse fails
     * without stripping — this handles both cases.
     */
    private fun readLoopingPkgs(prefs: android.content.SharedPreferences): Set<String> {
        val raw = prefs.getString("flutter.notif_looping_pkgs", null)
            ?: return emptySet()
        return try {
            // Strip Flutter's StringList prefix (everything up to and including '!')
            val json = if (raw.contains('!')) raw.substringAfter('!') else raw
            val arr = JSONArray(json)
            (0 until arr.length()).map { arr.getString(it) }.toSet()
        } catch (e: Throwable) {
            Log.e("NotifLED", "readLoopingPkgs parse failed: ${e.message}")
            emptySet()
        }
    }

    // ── Trigger strategies ────────────────────────────────────────────────────

    /**
     * Non-looping: 2 hardware writes with a 1.5s gap.
     * Each write produces 2–4 natural flashes on the aw22xxx, so 2 writes
     * gives a noticeable double-burst. Cooldown is set AFTER both writes
     * so the 6s window correctly covers the full sequence.
     *
     * Looping: 1 write, then a 5s auto-stop timer. The timer is cancelled
     * if onNotificationRemoved fires first (notification cleared early).
     */
    private fun triggerEffect(pkg: String, hex: String, isLooping: Boolean) {
        Log.d("NotifLED", "Trigger [$pkg] looping=$isLooping hex='$hex'")

        if (isLooping) {
            synchronized(activeLoopingPkgs) { activeLoopingPkgs.add(pkg) }
        }

        val wl = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "LEDSync:trigger:$pkg"
        )
        wl.acquire(10_000L)

        thread {
            try {
                fireEffect(hex, "FIRE1[$pkg]")

                if (!isLooping) {
                    // Write 2 after delay — set cooldown only after both writes done
                    Thread.sleep(DOUBLE_FIRE_DELAY_MS)
                    fireEffect(hex, "FIRE2[$pkg]")
                    synchronized(lastTriggerPerPkg) {
                        lastTriggerPerPkg[pkg] = System.currentTimeMillis()
                    }
                } else {
                    // Auto-stop after 5 s if notification wasn't cleared yet
                    handler.postDelayed({
                        val stillActive = synchronized(activeLoopingPkgs) {
                            activeLoopingPkgs.contains(pkg)
                        }
                        if (stillActive) {
                            Log.d("NotifLED", "Loop auto-stop (5s) [$pkg]")
                            synchronized(activeLoopingPkgs) { activeLoopingPkgs.remove(pkg) }
                            val prefs = applicationContext.getSharedPreferences(
                                "FlutterSharedPreferences", Context.MODE_PRIVATE
                            )
                            val off = prefs.getString("flutter.notif_turnoff_hex",
                                "00 01 00 00 00 00") ?: "00 01 00 00 00 00"
                            thread { fireStop(off, "AUTO_STOP[$pkg]") }
                        }
                    }, LOOP_AUTO_STOP_MS)
                }
            } finally {
                if (wl.isHeld) wl.release()
            }
        }
    }

    // ── Notification callbacks ─────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName ?: return

            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )

            val raw = prefs.getString("flutter.notif_hex_map", null)
            if (raw.isNullOrBlank()) {
                Log.d("NotifLED", "notif_hex_map empty — set mapping in App LED Sync and Save")
                return
            }

            val hex = try {
                JSONObject(raw).optString(pkg, "")
            } catch (e: Throwable) {
                Log.e("NotifLED", "JSON parse failed", e)
                ""
            }

            if (hex.isBlank()) {
                Log.d("NotifLED", "No mapping for $pkg")
                return
            }

            val loopingPkgs = readLoopingPkgs(prefs)
            val isLooping = loopingPkgs.contains(pkg)

            if (isLooping) {
                // Already running — don't re-fire while LED is active.
                val alreadyActive = synchronized(activeLoopingPkgs) {
                    activeLoopingPkgs.contains(pkg)
                }
                if (alreadyActive) {
                    Log.d("NotifLED", "Loop already active for $pkg, skip")
                    return
                }
            } else {
                // Cooldown — don't re-fire while a recent trigger is still fresh.
                val now = System.currentTimeMillis()
                val last = synchronized(lastTriggerPerPkg) { lastTriggerPerPkg[pkg] ?: 0L }
                if (now - last < SEQUENCE_COOLDOWN_MS) {
                    Log.d("NotifLED", "Cooldown active for $pkg, skip")
                    return
                }
            }

            triggerEffect(pkg, hex, isLooping)

        } catch (e: Throwable) {
            Log.e("NotifLED", "onNotificationPosted crashed", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName ?: return

            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )

            // Only looping patterns need an explicit stop.
            val loopingPkgs = readLoopingPkgs(prefs)
            if (!loopingPkgs.contains(pkg)) return

            // Keep LED running if the same app still has other active notifications.
            val stillActive = activeNotifications?.any { it.packageName == pkg } ?: false
            if (stillActive) {
                Log.d("NotifLED", "onRemoved: $pkg still has active notifs, keep LED")
                return
            }

            val turnOffHex = prefs.getString("flutter.notif_turnoff_hex", "00 01 00 00 00 00")
                ?: "00 01 00 00 00 00"

            Log.d("NotifLED", "onRemoved: stopping loop for $pkg")
            synchronized(activeLoopingPkgs) { activeLoopingPkgs.remove(pkg) }

            val wl = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK, "LEDSync:stop:$pkg"
            )
            wl.acquire(5_000L)
            thread {
                try {
                    fireStop(turnOffHex, "STOP_LOOP[$pkg]")
                } finally {
                    if (wl.isHeld) wl.release()
                }
            }

        } catch (e: Throwable) {
            Log.e("NotifLED", "onNotificationRemoved crashed", e)
        }
    }
}