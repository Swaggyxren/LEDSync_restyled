package com.xiiann.ledsync

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.DataOutputStream
import kotlin.concurrent.thread
import kotlin.jvm.Volatile

class NotificationLedService : NotificationListenerService() {

    // Matches your LH8nConfig
    private val LB_CMD_PATH = "/sys/led/led/tran_led_cmd"
    private val HWEN_PATH = "/sys/class/leds/aw22xxx_led/hwen"
    private val BRIGHT_PATH = "/sys/class/leds/aw22xxx_led/brightness"

    private val PULSE_INTERVAL_MS = 1500L
    private val COOLDOWN_MS = 1500L

    @Volatile
    private var lastTriggerTimeMillis: Long = 0L

    // Tracks packages whose looping LED is currently ON.
    // Prevents re-triggering while the pattern is already running.
    private val activeLoopingPkgs = mutableSetOf<String>()

    private val handler = Handler(Looper.getMainLooper())

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d("NotifLED", "Listener CONNECTED ✅")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d("NotifLED", "Listener DISCONNECTED ❌")
    }

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

    private fun ensureEngineOn(): Boolean {
        val ok1 = runSu("echo 1 > $HWEN_PATH")
        val ok2 = runSu("echo 255 > $BRIGHT_PATH")
        Log.d("NotifLED", "ensureEngineOn: hwen=$ok1 bright=$ok2")
        return ok1 && ok2
    }

    private fun fireOnce(hex: String, tag: String): Boolean {
        // keep quotes exactly like this so spaces stay intact
        val ok = runSu("echo -n '$hex' > $LB_CMD_PATH")
        Log.d("NotifLED", "$tag -> cmd=$ok hex='$hex'")
        return ok
    }

    private fun triggerTwice(pkg: String, hex: String) {
        Log.d("NotifLED", "Trigger x2 for: $pkg hex='$hex'")
        lastTriggerTimeMillis = System.currentTimeMillis()

        // Do root writes off the listener thread (avoid blocking)
        thread {
            ensureEngineOn()
            fireOnce(hex, "FIRE #1")

            // second fire after 1.5s gap
            handler.postDelayed({
                thread {
                    ensureEngineOn()
                    fireOnce(hex, "FIRE #2")
                }
            }, PULSE_INTERVAL_MS)
        }
    }

    // Used for looping patterns — one write is enough since the hardware
    // keeps the pattern running until explicitly stopped.
    private fun triggerOnce(pkg: String, hex: String) {
        Log.d("NotifLED", "Trigger x1 (looping) for: $pkg hex='$hex'")
        lastTriggerTimeMillis = System.currentTimeMillis()
        synchronized(activeLoopingPkgs) { activeLoopingPkgs.add(pkg) }

        thread {
            ensureEngineOn()
            fireOnce(hex, "FIRE_LOOP[$pkg]")
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName ?: return

            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )

            val raw = prefs.getString("flutter.notif_hex_map", null)
            if (raw.isNullOrBlank()) {
                Log.d("NotifLED", "flutter.notif_hex_map is EMPTY/NULL (open App LED Sync -> set mapping -> Save)")
                return
            }

            val hex = try {
                val obj = JSONObject(raw)
                obj.optString(pkg, "")
            } catch (e: Throwable) {
                Log.e("NotifLED", "JSON parse failed", e)
                ""
            }

            if (hex.isBlank()) {
                Log.d("NotifLED", "No mapping for package: $pkg")
                return
            }

            // Check if this package uses a looping pattern.
            val loopingPkgs = prefs.getStringSet("flutter.notif_looping_pkgs", emptySet())
                ?: emptySet()
            val isLooping = loopingPkgs.contains(pkg)

            if (isLooping) {
                // Looping pattern: only fire if not already running for this package.
                // This ensures the LED triggers exactly once per notification session —
                // it keeps running until the notification is cleared, no re-fires.
                val alreadyActive = synchronized(activeLoopingPkgs) { activeLoopingPkgs.contains(pkg) }
                if (alreadyActive) {
                    Log.d("NotifLED", "Looping already active for $pkg, skip re-trigger")
                    return
                }
                triggerOnce(pkg, hex)
            } else {
                // One-shot pattern: use the existing cooldown + double-fire logic.
                val now = System.currentTimeMillis()
                if (now - lastTriggerTimeMillis < COOLDOWN_MS) {
                    Log.d("NotifLED", "Cooldown: skipping $pkg")
                    return
                }
                triggerTwice(pkg, hex)
            }

        } catch (e: Throwable) {
            Log.e("NotifLED", "onNotificationPosted crashed", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName ?: return

            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )

            // Only act if this package is assigned a looping pattern.
            // Non-looping patterns (Halo, Lightning, Pureness, etc.) self-terminate
            // after their animation cycle — no cleanup needed.
            val loopingPkgs = prefs.getStringSet("flutter.notif_looping_pkgs", emptySet())
                ?: emptySet()
            if (!loopingPkgs.contains(pkg)) {
                Log.d("NotifLED", "onRemoved: $pkg not looping, skip")
                return
            }

            // If the same app still has other active notifications, keep the LED running.
            val stillActive = activeNotifications?.any { it.packageName == pkg } ?: false
            if (stillActive) {
                Log.d("NotifLED", "onRemoved: $pkg still has active notifs, keep LED")
                return
            }

            // Last notification from this package is gone — stop the looping LED.
            val turnOffHex = prefs.getString("flutter.notif_turnoff_hex", "00 01 00 00 00 00")
                ?: "00 01 00 00 00 00"

            Log.d("NotifLED", "onRemoved: stopping looping LED for $pkg hex='$turnOffHex'")
            synchronized(activeLoopingPkgs) { activeLoopingPkgs.remove(pkg) }
            thread {
                fireOnce(turnOffHex, "STOP_LOOP[$pkg]")
            }

        } catch (e: Throwable) {
            Log.e("NotifLED", "onNotificationRemoved crashed", e)
        }
    }
}