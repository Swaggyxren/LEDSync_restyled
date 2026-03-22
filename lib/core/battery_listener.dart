import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

class BatteryListener {
  static final Battery _battery = Battery();

  // ── SharedPreferences cached once — was re-instantiated on every event ───
  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  static const String kBattLowEffectNameKey      = 'batt_low_effect_name';
  static const String kBattCriticalEffectNameKey  = 'batt_critical_effect_name';
  static const String kBattFullEffectNameKey      = 'batt_full_effect_name';
  static const String kBattLowThresholdKey        = 'batt_low_threshold';
  static const String kBattCriticalThresholdKey   = 'batt_critical_threshold';
  static const String kBattFullThresholdKey       = 'batt_full_threshold';

  static const String kDefaultLowEffect = 'Rise';
  static const String kDefaultCriticalEffect = 'Lightning';
  static const String kDefaultFullEffect = 'Pureness';

  static bool _inLow      = false;
  static bool _inCritical = false;
  static bool _inFull     = false;
  static const int _hysteresis = 2;

  static const Duration kLowCriticalPulseInterval = Duration(milliseconds: 1500);
  static const int      kLowCriticalPulseCount    = 5;
  static const Duration kFullPulseInterval        = Duration(seconds: 3);

  static Timer? _lowCritTimer;
  static int    _lowCritRemaining = 0;
  static Timer? _fullTimer;

  static bool _started = false;
  static Timer? _pollTimer;

  static void listen() {
    if (_started) return;
    _started = true;

    _battery.onBatteryStateChanged.listen((_) async {
      await _checkNow();
    });

    // Threshold crossing (e.g., 10 -> 9) may not emit a state-change event,
    // so poll battery level periodically.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      await _checkNow();
    });

    _checkNow();
  }

  static Future<void> _checkNow() async {
    try {
      final results = await Future.wait([
        _battery.batteryLevel,
        _battery.batteryState,
      ]);
      await _handleBattery(
        level: results[0] as int,
        state: results[1] as BatteryState,
      );
    } catch (_) {}
  }

  static Future<void> _handleBattery({
    required int level,
    required BatteryState state,
  }) async {
    if (!RootLogic.masterEnabled) return;

    final sp  = await _sp;
    final cfg = await RootLogic.getConfig();
    if (cfg == null) return;

    final lowTh  = (sp.getInt(kBattLowThresholdKey)      ?? 20).clamp(5,  50);
    final critTh = (sp.getInt(kBattCriticalThresholdKey) ?? 10).clamp(1,  30);
    final fullTh = (sp.getInt(kBattFullThresholdKey)     ?? 100).clamp(90, 100);

    final lowName = _resolveEffectName(
      sp.getString(kBattLowEffectNameKey),
      fallback: kDefaultLowEffect,
      cfg: cfg,
    );
    final critName = _resolveEffectName(
      sp.getString(kBattCriticalEffectNameKey),
      fallback: kDefaultCriticalEffect,
      cfg: cfg,
    );
    final fullName = _resolveEffectName(
      sp.getString(kBattFullEffectNameKey),
      fallback: kDefaultFullEffect,
      cfg: cfg,
    );

    final nowCritical = level <= critTh;
    final nowLow      = level <= lowTh && !nowCritical;
    final charging    = state == BatteryState.charging || state == BatteryState.full;
    final nowFull     = charging && level >= fullTh;

    final wasInFull = _inFull;

    if (_inCritical && level >= critTh + _hysteresis) {
      _inCritical = false;
      _cancelLowCritTimer();
    }
    if (_inLow      && level >= lowTh  + _hysteresis) {
      _inLow = false;
      _cancelLowCritTimer();
    }
    if (_inFull && (!charging || level <= fullTh - _hysteresis)) {
      _inFull = false;
      _cancelFullTimer();
    }

    // Full-charge indication should stop once power is unplugged.
    if (wasInFull && !_inFull && !charging) {
      _cancelFullTimer();
      await RootLogic.turnOffAll();
    }

    if (nowCritical && !_inCritical) {
      _inCritical = _inLow = true;
      await _playByName(cfg, critName);
      _startLowCriticalTrain();
      return;
    }
    if (nowLow && !_inLow) {
      _inLow = true;
      await _playByName(cfg, lowName);
      _startLowCriticalTrain();
      return;
    }
    if (nowFull && !_inFull) {
      _inFull = true;
      await _playByName(cfg, fullName);
      _startFullTimer();
    }
  }

  static void _startLowCriticalTrain() {
    _cancelLowCritTimer();
    _lowCritRemaining = kLowCriticalPulseCount - 1; // one pulse already fired on entry
    if (_lowCritRemaining <= 0) return;
    _lowCritTimer = Timer.periodic(
      kLowCriticalPulseInterval,
      (_) => _pulseLowCriticalEffect(),
    );
  }

  static Future<void> _pulseLowCriticalEffect() async {
    if (!RootLogic.masterEnabled || (!_inCritical && !_inLow)) {
      _cancelLowCritTimer();
      return;
    }
    if (_lowCritRemaining <= 0) {
      _cancelLowCritTimer();
      return;
    }
    _lowCritRemaining--;

    final cfg = await RootLogic.getConfig();
    if (cfg == null) {
      _cancelLowCritTimer();
      return;
    }
    final sp = await _sp;
    final lowName = _resolveEffectName(
      sp.getString(kBattLowEffectNameKey),
      fallback: kDefaultLowEffect,
      cfg: cfg,
    );
    final critName = _resolveEffectName(
      sp.getString(kBattCriticalEffectNameKey),
      fallback: kDefaultCriticalEffect,
      cfg: cfg,
    );
    final String? effectName = _inCritical ? critName : (_inLow ? lowName : null);
    await _playByName(cfg, effectName);

    if (_lowCritRemaining <= 0) {
      _cancelLowCritTimer();
    }
  }

  static void _startFullTimer() {
    _cancelFullTimer();
    _fullTimer = Timer.periodic(
      kFullPulseInterval,
      (_) => _pulseFullEffect(),
    );
  }

  static Future<void> _pulseFullEffect() async {
    if (!RootLogic.masterEnabled || !_inFull) {
      _cancelFullTimer();
      return;
    }
    final cfg = await RootLogic.getConfig();
    if (cfg == null) {
      _cancelFullTimer();
      return;
    }
    final sp = await _sp;
    final fullName = _resolveEffectName(
      sp.getString(kBattFullEffectNameKey),
      fallback: kDefaultFullEffect,
      cfg: cfg,
    );
    await _playByName(cfg, fullName);
  }

  static void _cancelLowCritTimer() {
    _lowCritTimer?.cancel();
    _lowCritTimer = null;
    _lowCritRemaining = 0;
  }

  static void _cancelFullTimer() {
    _fullTimer?.cancel();
    _fullTimer = null;
  }

  static String? _resolveEffectName(
    String? raw, {
    required String fallback,
    required DeviceConfig cfg,
  }) {
    final name = raw?.trim();
    if (name != null && name.isNotEmpty && cfg.ledEffects.containsKey(name)) {
      return name;
    }
    if (cfg.ledEffects.containsKey(fallback)) {
      return fallback;
    }
    return null;
  }

  static Future<void> _playByName(DeviceConfig cfg, String? effectName) async {
    if (effectName == null) return;
    final hex = cfg.ledEffects[effectName];
    if (hex == null || hex.trim().isEmpty) return;
    await RootLogic.sendRawHex(hex);
  }

  static Future<void> refreshNow() => _checkNow();
}

