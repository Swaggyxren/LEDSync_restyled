import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledsync/models/devices/device_config.dart';
import 'package:ledsync/models/devices/lh8n_config.dart';

class RootLogic {
  static bool masterEnabled = true;
  static bool? _cachedRooted;

  // ── Active config — user-chosen, persisted ─────────────────────────────
  static DeviceConfig? _currentConfig;

  static final List<DeviceConfig> allConfigs = [
    LH8nConfig(),
    // Add future device configs here
  ];

  static const _kConfigPrefKey = 'selected_device_config';

  /// Returns the active config. Loads from prefs on first call.
  /// Defaults to LH8nConfig if nothing is saved yet — never returns null.
  static Future<DeviceConfig> getConfig() async {
    if (_currentConfig != null) return _currentConfig!;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kConfigPrefKey);

    _currentConfig = allConfigs.firstWhere(
      (c) => c.deviceName == saved,
      orElse: () => LH8nConfig(),
    );
    return _currentConfig!;
  }

  /// Sync getter for use after getConfig() has been awaited at least once.
  static DeviceConfig? get activeConfig => _currentConfig;

  /// Set and persist the user's chosen config.
  static Future<void> setConfig(DeviceConfig cfg) async {
    _currentConfig = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConfigPrefKey, cfg.deviceName);
  }

  static Future<bool> isRooted() async {
    if (_cachedRooted != null) return _cachedRooted!;
    try {
      final r = await Process.run('su', ['-v']);
      _cachedRooted = r.exitCode == 0;
    } catch (_) {
      _cachedRooted = false;
    }
    return _cachedRooted!;
  }

  static Future<Map<String, dynamic>> getPhoneInfo() async {
    final results = await Future.wait([
      DeviceInfoPlugin().androidInfo,
      Process.run('su', ['-c', 'uname -r']),
    ]);

    final androidInfo = results[0] as AndroidDeviceInfo;
    final kernelResult = results[1] as ProcessResult;
    final cfg = await getConfig();

    return {
      'model': cfg.deviceName,
      'version': 'Android ${androidInfo.version.release}',
      'kernel': kernelResult.stdout.toString().trim(),
    };
  }

  static Future<void> initializeHardware() => ensureLedEnabled();

  static Future<void> ensureLedEnabled() async {
    final cfg = await getConfig();
    await _runSu(
      'echo 1 > ${cfg.awPath}/hwen; '
      'echo c > ${cfg.awPath}/imax 2>/dev/null || true; '
      'echo 255 > ${cfg.awPath}/brightness; '
      'echo none > ${cfg.awPath}/trigger 2>/dev/null || true; '
      "echo -n '00 00 00 00 00 00' > ${cfg.lbCmd}",
    );
  }

  static Future<void> sendRawHex(String hex) async {
    if (!masterEnabled) return;
    final cfg = await getConfig();
    // Two su calls: first resets the controller, second writes the effect.
    // The hardware needs the reset to fully complete before accepting the effect.
    await ensureLedEnabled();
    await _runSu("echo -n '$hex' > ${cfg.lbCmd}");
  }

  static Future<void> turnOffAll() async {
    final cfg = await getConfig();
    await _runSu(
      "echo -n '${cfg.turnOffHex}' > ${cfg.lbCmd}; "
      'echo 0 > ${cfg.awPath}/brightness; '
      'echo 0 > ${cfg.awPath}/hwen',
    );
  }

  static Future<void> emergencyKillAndRevive({
    Duration offTime = const Duration(milliseconds: 250),
  }) async {
    await turnOffAll();
    await Future.delayed(offTime);
    await ensureLedEnabled();
  }

  static Future<ProcessResult> _runSu(String cmd) async {
    final result = await Process.run('su', ['-c', cmd]);
    if (result.exitCode != 0) {
      debugPrint('[RootLogic] su failed (exit ${result.exitCode}): $cmd');
    }
    return result;
  }
}
