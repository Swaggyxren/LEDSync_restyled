import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

class BatteryListener {
  static final Battery _battery = Battery();

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  static const String kBattLowEffectNameKey = 'batt_low_effect_name';
  static const String kBattCriticalEffectNameKey = 'batt_critical_effect_name';
  static const String kBattFullEffectNameKey = 'batt_full_effect_name';
  static const String kBattLowThresholdKey = 'batt_low_threshold';
  static const String kBattCriticalThresholdKey = 'batt_critical_threshold';
  static const String kBattFullThresholdKey = 'batt_full_threshold';

  static bool _inLow = false;
  static bool _inCritical = false;
  static bool _inFull = false;
  static const int _hysteresis = 2;

  // Non-looping: 5 pulses at 2 s intervals
  static const Duration kPulseInterval = Duration(seconds: 2);
  static const int kPulseCount = 5;
  static const Duration kFullPulseInterval = Duration(seconds: 3);

  static Timer? _lowCritTimer;
  static int _lowCritRemaining = 0;
  static Timer? _fullTimer;
  static Timer? _loopStopTimer;

  static bool _started = false;
  static Timer? _pollTimer;

  // ── Public ─────────────────────────────────────────────────────────────────

  static void listen() {
    if (_started) return;
    _started = true;

    _battery.onBatteryStateChanged.listen((_) async {
      debugPrint('[BattLED] onBatteryStateChanged fired');
      await _checkNow();
    });

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      debugPrint('[BattLED] poll tick');
      await _checkNow();
    });

    _checkNow();
  }

  static Future<void> refreshNow() => _checkNow();

  // ── Core ───────────────────────────────────────────────────────────────────

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
    } catch (e) {
      debugPrint('[BattLED] _checkNow error: $e');
    }
  }

  static Future<void> _handleBattery({
    required int level,
    required BatteryState state,
  }) async {
    if (!RootLogic.masterEnabled) {
      debugPrint('[BattLED] masterEnabled=false, skipping');
      return;
    }

    final sp = await _sp;
    final cfg = await RootLogic.getConfig();

    final lowTh = (sp.getInt(kBattLowThresholdKey) ?? 20).clamp(5, 50);
    final critTh = (sp.getInt(kBattCriticalThresholdKey) ?? 10).clamp(1, 30);
    final fullTh = (sp.getInt(kBattFullThresholdKey) ?? 100).clamp(90, 100);

    final charging =
        state == BatteryState.charging || state == BatteryState.full;

    debugPrint(
      '[BattLED] level=$level charging=$charging '
      'lowTh=$lowTh critTh=$critTh fullTh=$fullTh '
      '_inLow=$_inLow _inCritical=$_inCritical _inFull=$_inFull',
    );

    final lowName = _resolveEffectName(
      sp.getString(kBattLowEffectNameKey),
      fallback: cfg.defaultLowEffect,
      cfg: cfg,
    );
    final critName = _resolveEffectName(
      sp.getString(kBattCriticalEffectNameKey),
      fallback: cfg.defaultCriticalEffect,
      cfg: cfg,
    );
    final fullName = _resolveEffectName(
      sp.getString(kBattFullEffectNameKey),
      fallback: cfg.defaultFullEffect,
      cfg: cfg,
    );

    debugPrint(
      '[BattLED] effects — low=$lowName crit=$critName full=$fullName',
    );

    final nowCritical = level <= critTh;
    final nowLow = level <= lowTh && !nowCritical;
    final nowFull = charging && level >= fullTh;

    final wasInFull = _inFull;

    // ── Exit hysteresis ───────────────────────────────────────────────────────
    if (_inCritical && level >= critTh + _hysteresis) {
      debugPrint('[BattLED] exiting critical state');
      _inCritical = false;
      _cancelLowCritTimer();
      _cancelLoopStopTimer();
      if (critName != null && cfg.loopingPatterns.contains(critName)) {
        await RootLogic.turnOffAll();
      }
    }
    if (_inLow && level >= lowTh + _hysteresis) {
      debugPrint('[BattLED] exiting low state');
      _inLow = false;
      _cancelLowCritTimer();
      _cancelLoopStopTimer();
      if (lowName != null && cfg.loopingPatterns.contains(lowName)) {
        await RootLogic.turnOffAll();
      }
    }
    if (_inFull && (!charging || level <= fullTh - _hysteresis)) {
      debugPrint('[BattLED] exiting full state');
      _inFull = false;
      _cancelFullTimer();
      _cancelLoopStopTimer();
    }

    if (wasInFull && !_inFull && !charging) {
      debugPrint('[BattLED] unplugged from full — turning off');
      _cancelFullTimer();
      await RootLogic.turnOffAll();
    }

    // ── Threshold entry ───────────────────────────────────────────────────────
    if (nowCritical && !_inCritical) {
      debugPrint('[BattLED] ENTERING critical — firing $critName');
      _inCritical = _inLow = true;
      await _playByName(cfg, critName);
      if (critName != null && cfg.loopingPatterns.contains(critName)) {
        _startLoopStopTimer();
      } else {
        _startPulseTrain(isCrit: true);
      }
      return;
    }

    if (nowLow && !_inLow) {
      debugPrint('[BattLED] ENTERING low — firing $lowName');
      _inLow = true;
      await _playByName(cfg, lowName);
      if (lowName != null && cfg.loopingPatterns.contains(lowName)) {
        _startLoopStopTimer();
      } else {
        _startPulseTrain(isCrit: false);
      }
      return;
    }

    if (nowFull && !_inFull) {
      debugPrint('[BattLED] ENTERING full — firing $fullName');
      _inFull = true;
      await _playByName(cfg, fullName);
      if (fullName != null && cfg.loopingPatterns.contains(fullName)) {
        _startLoopStopTimer();
      } else {
        _startFullTimer();
      }
      return;
    }

    debugPrint(
      '[BattLED] no threshold change — nowCrit=$nowCritical nowLow=$nowLow nowFull=$nowFull',
    );
  }

  // ── 10 s auto-stop for looping battery patterns ────────────────────────────

  static void _startLoopStopTimer() {
    _cancelLoopStopTimer();
    debugPrint('[BattLED] starting 10 s loop stop timer');
    _loopStopTimer = Timer(const Duration(seconds: 10), () async {
      debugPrint('[BattLED] 10 s elapsed — stopping looping pattern');
      await RootLogic.turnOffAll();
      _loopStopTimer = null;
    });
  }

  static void _cancelLoopStopTimer() {
    _loopStopTimer?.cancel();
    _loopStopTimer = null;
  }

  // ── Pulse train — non-looping ──────────────────────────────────────────────

  static void _startPulseTrain({required bool isCrit}) {
    _cancelLowCritTimer();
    _lowCritRemaining = kPulseCount - 1;
    debugPrint(
      '[BattLED] starting pulse train — $_lowCritRemaining more pulses at ${kPulseInterval.inSeconds}s',
    );
    if (_lowCritRemaining <= 0) return;
    _lowCritTimer = Timer.periodic(kPulseInterval, (_) async {
      await _pulseLowCritEffect(isCrit: isCrit);
    });
  }

  static Future<void> _pulseLowCritEffect({required bool isCrit}) async {
    if (!RootLogic.masterEnabled || (!_inCritical && !_inLow)) {
      _cancelLowCritTimer();
      return;
    }
    if (_lowCritRemaining <= 0) {
      _cancelLowCritTimer();
      return;
    }
    _lowCritRemaining--;
    debugPrint('[BattLED] pulse — remaining=$_lowCritRemaining');

    final cfg = await RootLogic.getConfig();
    final sp = await _sp;

    final critName = _resolveEffectName(
      sp.getString(kBattCriticalEffectNameKey),
      fallback: cfg.defaultCriticalEffect,
      cfg: cfg,
    );
    final lowName = _resolveEffectName(
      sp.getString(kBattLowEffectNameKey),
      fallback: cfg.defaultLowEffect,
      cfg: cfg,
    );

    final effectName = _inCritical ? critName : (_inLow ? lowName : null);
    if (effectName != null && cfg.loopingPatterns.contains(effectName)) {
      _cancelLowCritTimer();
      return;
    }
    await _playByName(cfg, effectName);
    if (_lowCritRemaining <= 0) _cancelLowCritTimer();
  }

  // ── Full repeat — non-looping ──────────────────────────────────────────────

  static void _startFullTimer() {
    _cancelFullTimer();
    _fullTimer = Timer.periodic(kFullPulseInterval, (_) async {
      await _pulseFullEffect();
    });
  }

  static Future<void> _pulseFullEffect() async {
    if (!RootLogic.masterEnabled || !_inFull) {
      _cancelFullTimer();
      return;
    }
    final cfg = await RootLogic.getConfig();
    final sp = await _sp;
    final fullName = _resolveEffectName(
      sp.getString(kBattFullEffectNameKey),
      fallback: cfg.defaultFullEffect,
      cfg: cfg,
    );
    if (fullName != null && cfg.loopingPatterns.contains(fullName)) {
      _cancelFullTimer();
      return;
    }
    await _playByName(cfg, fullName);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

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
    if (cfg.ledEffects.containsKey(fallback)) return fallback;
    return null;
  }

  static Future<void> _playByName(DeviceConfig cfg, String? effectName) async {
    if (effectName == null) {
      debugPrint('[BattLED] _playByName — effectName is null, skipping');
      return;
    }
    final hex = cfg.ledEffects[effectName];
    if (hex == null || hex.trim().isEmpty) {
      debugPrint('[BattLED] _playByName — no hex for $effectName');
      return;
    }
    debugPrint('[BattLED] _playByName — sending $effectName hex=$hex');
    await RootLogic.sendRawHex(hex);
  }
}
