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

            val now = System.currentTimeMillis()
            if (now - lastTriggerTimeMillis < COOLDOWN_MS) {
                Log.d("NotifLED", "Cooldown: skipping $pkg")
                return
            }

            triggerTwice(pkg, hex)

        } catch (e: Throwable) {
            Log.e("NotifLED", "onNotificationPosted crashed", e)
        }
    }
}
