import 'package:ledsync/models/devices/device_config.dart';

class LH8nConfig implements DeviceConfig {
  @override
  String get deviceName => 'POVA 5 Pro (LH8n)';
  @override
  String get awPath => '/sys/class/leds/aw22xxx_led';
  @override
  String get lbCmd => '/sys/led/led/tran_led_cmd';

  @override
  Map<String, String> get ledEffects => {
    'Soft':      '00 04 00 00 00 00',
    'Speed':     '00 30 01 00 00 00',
    'Illusion':  '00 03 01 00 00 00',
    'Halo':      '00 05 01 02 00 00',
    'Lightning': '00 05 01 03 00 00',
    'Pureness':  '00 05 01 00 00 00',
    'StarRiver': '00 05 01 01 00 00',
    'Rise':      '00 05 01 04 00 00',
    'Breathe':   '00 20 02 00 00 00',
    'Party':     '00 20 03 00 00 00',
  };

  /// These patterns loop indefinitely after a single hardware write.
  /// A per-app rule using any of these must stop the LED when the
  /// triggering notification is dismissed.
  @override
  Set<String> get loopingPatterns => const {
    'Soft',
    'Speed',
    'Illusion',
    'Breathe',
    'Party',
  };

  @override
  String get turnOffHex => '00 01 00 00 00 00';
}