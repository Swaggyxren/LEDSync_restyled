import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ledsync/main.dart' show kConsoleBg, kConsoleBorder, kPrimary;
import 'package:ledsync/core/system_log.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scroll = ScrollController();
  final _log = SystemLog.instance;

  @override
  void initState() {
    super.initState();
    _log.version.addListener(_onNewLog);
  }

  @override
  void dispose() {
    _log.version.removeListener(_onNewLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  static Color _lvlColor(SystemLogLevel l) {
    switch (l) {
      case SystemLogLevel.success: return const Color(0xFF4ADE80);
      case SystemLogLevel.warning: return const Color(0xFFFBBF24);
      case SystemLogLevel.error:   return const Color(0xFFF87171);
      case SystemLogLevel.info:    return const Color(0xFF93C5FD);
    }
  }

  static String _lvlPrefix(SystemLogLevel l) {
    switch (l) {
      case SystemLogLevel.success: return '✓';
      case SystemLogLevel.warning: return '⚠';
      case SystemLogLevel.error:   return '✗';
      case SystemLogLevel.info:    return '›';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final topPad  = MediaQuery.of(context).padding.top;
    final entries = _log.entries;

    int nInfo = 0, nOk = 0, nWarn = 0, nErr = 0;
    for (final e in entries) {
      switch (e.level) {
        case SystemLogLevel.info:    nInfo++; break;
        case SystemLogLevel.success: nOk++;   break;
        case SystemLogLevel.warning: nWarn++; break;
        case SystemLogLevel.error:   nErr++;  break;
      }
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(children: [
        // ── Header ───────────────────────────────────────────────────────
        Container(
          color: cs.surface,
          padding: EdgeInsets.only(left: 20, right: 8, top: topPad + 8, bottom: 4),
          child: Row(children: [
            Text('System Logs',
                style: GoogleFonts.spaceGrotesk(
                    color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 22)),
            const Spacer(),
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('${entries.length}',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () { _log.clear(); setState(() {}); },
              icon: Icon(Icons.delete_sweep_outlined, color: cs.error),
              tooltip: 'Clear logs',
            ),
          ]),
        ),

        // ── Level badges ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            _badge('INFO', const Color(0xFF93C5FD), nInfo),
            const SizedBox(width: 6),
            _badge('OK',   const Color(0xFF4ADE80), nOk),
            const SizedBox(width: 6),
            _badge('WARN', const Color(0xFFFBBF24), nWarn),
            const SizedBox(width: 6),
            _badge('ERR',  const Color(0xFFF87171), nErr),
          ]),
        ),

        // ── Terminal panel ────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: kConsoleBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kConsoleBorder.withValues(alpha: 0.25)),
              ),
              child: Column(children: [
                // Terminal title bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                    border: Border(
                      bottom: BorderSide(color: kConsoleBorder.withValues(alpha: 0.15)),
                    ),
                  ),
                  child: Row(children: [
                    _dot(Colors.red.shade400),
                    const SizedBox(width: 5),
                    _dot(Colors.amber.shade400),
                    const SizedBox(width: 5),
                    _dot(Colors.green.shade400),
                    const SizedBox(width: 10),
                    Text('ledsync — system log',
                        style: TextStyle(color: cs.outline, fontSize: 10, fontFamily: 'monospace')),
                    const Spacer(),
                    Text('BAUD: 115200',
                        style: TextStyle(
                          color: kPrimary.withValues(alpha: 0.7),
                          fontSize: 10, fontFamily: 'monospace')),
                  ]),
                ),

                // Log list
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.terminal, color: cs.outline, size: 40),
                            const SizedBox(height: 12),
                            Text('No system logs yet',
                                style: TextStyle(color: cs.outline, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text('System events will appear here',
                                style: TextStyle(
                                  color: cs.outline.withValues(alpha: 0.6), fontSize: 12)),
                          ]),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(14),
                          itemCount: entries.length,
                          itemBuilder: (_, i) {
                            final e   = entries[i];
                            final col = _lvlColor(e.level);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('[${e.timeStr}] ',
                                      style: TextStyle(
                                        color: cs.outline.withValues(alpha: 0.55),
                                        fontSize: 11, fontFamily: 'monospace')),
                                  Text('${_lvlPrefix(e.level)} ',
                                      style: TextStyle(
                                        color: col, fontSize: 11,
                                        fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: Text(e.message,
                                        style: TextStyle(
                                          color: col.withValues(alpha: 0.9),
                                          fontSize: 11, fontFamily: 'monospace')),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Blinking cursor line
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Row(children: [
                    Text('> ', style: TextStyle(
                        color: kConsoleBorder.withValues(alpha: 0.7),
                        fontSize: 11, fontFamily: 'monospace')),
                    const _BlinkingCursor(),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _badge(String label, Color color, int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text('$label: $count',
            style: TextStyle(
              color: color, fontSize: 10,
              fontWeight: FontWeight.w600, fontFamily: 'monospace')),
      );

  Widget _dot(Color c) =>
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: c));
}

// ─── Blinking cursor ──────────────────────────────────────────────────────
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => Opacity(
          opacity: _ctrl.value > 0.5 ? 1 : 0,
          child: Container(width: 7, height: 13,
              color: kConsoleBorder.withValues(alpha: 0.7)),
        ),
      );
}
