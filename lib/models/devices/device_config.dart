abstract class DeviceConfig {
  String get deviceName;
  String get awPath;
  String get lbCmd;
  Map<String, String> get ledEffects;

  /// Patterns that loop infinitely until explicitly stopped.
  Set<String> get loopingPatterns;

  /// The raw hex command that turns all LEDs off on this device.
  String get turnOffHex => '00 01 00 00 00 00';

  /// Default effect names for battery threshold alerts.
  /// Each config defines its own so a new device never inherits
  /// another device's pattern names.
  String get defaultLowEffect;
  String get defaultCriticalEffect;
  String get defaultFullEffect;
}