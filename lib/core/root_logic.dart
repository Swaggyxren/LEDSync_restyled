import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ledsync/models/devices/device_config.dart';
import 'package:ledsync/models/devices/lh8n_config.dart';

class RootManagerInfo {
  final String name;
  final String iconPath;
  RootManagerInfo(this.name, this.iconPath);
}

class RootLogic {
  static DeviceConfig? _currentConfig;
  static bool masterEnabled = true;

  // ── Cached root check — only runs `su -v` once per app session ────────────
  static bool? _cachedRooted;

  static Future<DeviceConfig?> getConfig() async {
    if (_currentConfig != null) return _currentConfig;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.model.contains('LH8n')) {
      _currentConfig = LH8nConfig();
    }
    return _currentConfig;
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
    // Run all three reads in parallel instead of serially
    final results = await Future.wait([
      DeviceInfoPlugin().androidInfo,
      Process.run('su', ['-c', 'uname -r']),
      Process.run('getprop', ['ro.product.marketname']),
    ]);

    final androidInfo = results[0] as dynamic;
    final kernelResult = results[1] as ProcessResult;
    final marketResult = results[2] as ProcessResult;

    final marketName = marketResult.stdout.toString().trim();
    final displayName = marketName.isNotEmpty ? marketName : androidInfo.model as String;

    return {
      'model':   displayName,
      'version': 'Android ${androidInfo.version.release}',
      'kernel':  kernelResult.stdout.toString().trim(),
    };
  }

  static Future<RootManagerInfo> detectManager() async {
    if ((await _runSu('ls /data/adb/ksu')).exitCode == 0) {
      return RootManagerInfo('KernelSU Next', 'assets/kernelsu_next.png');
    }
    if ((await _runSu('ls /data/adb/apatch')).exitCode == 0) {
      return RootManagerInfo('APatch', 'assets/apatch_icon.png');
    }
    if ((await _runSu('magisk -v')).exitCode == 0) {
      return RootManagerInfo('Magisk', 'assets/magisk.png');
    }
    return RootManagerInfo('Unknown', '');
  }

  static Future<void> initializeHardware() => ensureLedEnabled();

  /// Batched into a single shell invocation — was 4 serial `su -c` calls.
  static Future<void> ensureLedEnabled() async {
    final cfg = await getConfig();
    if (cfg == null) return;
    // All commands joined with `;` → one Process.run instead of four
    await _runSu(
      'echo 1 > ${cfg.awPath}/hwen; '
      'echo c > ${cfg.awPath}/imax 2>/dev/null || true; '
      'echo 255 > ${cfg.awPath}/brightness; '
      'echo none > ${cfg.awPath}/trigger 2>/dev/null || true; '
      "echo -n '00 00 00 00 00 00' > ${cfg.lbCmd}",
    );
  }

  /// Send hex — always ensures hardware is primed first so repeated
  /// effect changes don't silently fail after the first write.
  static Future<void> sendRawHex(String hex) async {
    if (!masterEnabled) return;
    final cfg = await getConfig();
    if (cfg == null) return;
    // Re-enable hardware on every send — cheap (one shell cmd) and prevents
    // the "only fires once" bug where LED state drifts after first write.
    await ensureLedEnabled();
    await _runSu("echo -n '$hex' > ${cfg.lbCmd}");
  }

  /// Batched into a single shell invocation — was 3 serial `su -c` calls.
  static Future<void> turnOffAll() async {
    final cfg = await getConfig();
    if (cfg == null) return;
    await _runSu(
      "echo -n '00 01 00 00 00 00' > ${cfg.lbCmd}; "
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

  static Future<ProcessResult> _runSu(String cmd) =>
      Process.run('su', ['-c', cmd]);
}