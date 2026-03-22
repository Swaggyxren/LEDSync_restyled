abstract class DeviceConfig {
  String get deviceName;
  String get awPath;
  String get lbCmd;
  Map<String, String> get ledEffects;

  /// Patterns that loop infinitely until explicitly stopped.
  /// When one of these is assigned to a per-app notification rule,
  /// the LED engine must be stopped when the notification is cleared.
  Set<String> get loopingPatterns;

  /// The raw hex command that turns all LEDs off on this device.
  String get turnOffHex => '00 01 00 00 00 00';
}