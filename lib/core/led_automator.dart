import 'dart:async';
import 'package:ledsync/core/root_logic.dart';

enum LedPriority { notification, battery, idle }

class LedAutomator {
  static LedPriority _currentPriority = LedPriority.idle;
  static Timer? _cooldownTimer;

  // Optional: track if we recently emergency-killed, mostly for UI/debug
  static bool _wasEmergencyKilled = false;

  static LedPriority get currentPriority => _currentPriority;
  static bool get wasEmergencyKilled => _wasEmergencyKilled;

  static Future<void> playEffect({
    required String hex,
    required LedPriority priority,
    Duration cooldown = const Duration(seconds: 5),
  }) async {
    // PRIORITY LOGIC:
    // Notifications (Priority 1) can override Battery (Priority 2).
    // Battery CANNOT override an active Notification cooldown.
    if (_currentPriority == LedPriority.notification &&
        priority == LedPriority.battery) {
      return;
    }

    _currentPriority = priority;

    try {
      // 🔧 IMPORTANT FIX:
      // Always "wake"/re-enable the LED engine first so Emergency Kill
      // doesn't leave it permanently dead (hwen=0 etc).
      await RootLogic.ensureLedEnabled();

      // Send the command to the hardware
      await RootLogic.sendRawHex(hex);

      _wasEmergencyKilled = false;
    } catch (_) {
      // If root commands fail, don't leave priority stuck
      _currentPriority = LedPriority.idle;
      rethrow;
    } finally {
      // Handle Cooldown
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(cooldown, () {
        _currentPriority = LedPriority.idle;
      });
    }
  }

  /// Emergency kill that does NOT "kill forever":
  /// turns LEDs off immediately, then re-enables the controller so future
  /// effects/notifications work right away.
  static Future<void> emergencyKill({
    Duration offTime = const Duration(milliseconds: 250),
  }) async {
    // Optional: cancel cooldown so it doesn't block follow-up effects
    _cooldownTimer?.cancel();
    _currentPriority = LedPriority.idle;

    _wasEmergencyKilled = true;

    // This should do: lb_close + aw_off, wait, then aw_enable + lb_open
    await RootLogic.emergencyKillAndRevive(offTime: offTime);
  }
}
