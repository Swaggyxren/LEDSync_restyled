// ─── System Log ────────────────────────────────────────────────────────────
// Singleton that holds ONLY system / init events:
//   • app boot, root check result
//   • hardware initialisation
//   • service restart status
// System log store — persists across app lifetime.
// LedMenu console never reads this.
import 'package:flutter/foundation.dart';

enum SystemLogLevel { info, success, warning, error }

class SystemLogEntry {
  final DateTime timestamp;
  final String message;
  final SystemLogLevel level;

  SystemLogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  String get timeStr {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }
}

class SystemLog {
  SystemLog._();
  static final SystemLog instance = SystemLog._();

  final List<SystemLogEntry> _entries = [];
  final ValueNotifier<int> version = ValueNotifier(0);
  static const int _maxEntries = 500;

  List<SystemLogEntry> get entries => List.unmodifiable(_entries);

  void log(String message, {SystemLogLevel level = SystemLogLevel.info}) {
    _entries.add(
      SystemLogEntry(timestamp: DateTime.now(), message: message, level: level),
    );
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    version.value++;
  }

  void clear() {
    _entries.clear();
    version.value++;
  }
}
