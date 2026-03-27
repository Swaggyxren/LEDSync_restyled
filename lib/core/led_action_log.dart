// ─── LED Action Log ────────────────────────────────────────────────────────
// Singleton that holds ONLY LED hardware events:
//   • effect changes  (Breathing, Strobe, Rainbow …)
//   • emergency kill / restart
// Displayed exclusively in the LedMenu system console.
// LED action log — consumed by LedMenu console.
import 'package:flutter/foundation.dart';

enum LedActionLevel { info, success, warning, error }

class LedActionEntry {
  final DateTime timestamp;
  final String message;
  final LedActionLevel level;

  LedActionEntry({
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

class LedActionLog {
  LedActionLog._();
  static final LedActionLog instance = LedActionLog._();

  final List<LedActionEntry> _entries = [];
  final ValueNotifier<int> version = ValueNotifier(0);
  static const int _maxEntries = 500;

  List<LedActionEntry> get entries => List.unmodifiable(_entries);

  void log(String message, {LedActionLevel level = LedActionLevel.info}) {
    _entries.add(
      LedActionEntry(timestamp: DateTime.now(), message: message, level: level),
    );
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    version.value++;
  }

  void clear() {
    _entries.clear();
    version.value++;
  }
}
