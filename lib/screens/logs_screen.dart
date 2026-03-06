import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:ledsync/main.dart' show kPrimary, kTextDim, kNavBarClearance;
import 'package:ledsync/core/system_log.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scroll = ScrollController();
  final _log = SystemLog.instance;   // system events only — never generates new ones

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
      case SystemLogLevel.success: return const Color(0xFF22C55E);
      case SystemLogLevel.warning: return const Color(0xFFF59E0B);
      case SystemLogLevel.error:   return const Color(0xFFEF4444);
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

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0a0a14), Color(0xFF0f1d2f)],
        ),
      ),
      child: Stack(children: [
        Positioned(top: -60, right: -60,
          child: Container(width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: kPrimary.withValues(alpha: 0.08),
              boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.08),
                  blurRadius: 80, spreadRadius: 30)]))),

        Column(children: [
          Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: topPad + 16, bottom: 8),
            child: Row(children: [
              Text('System Logs', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
                ),
                child: Text('${entries.length}',
                    style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { _log.clear(); setState(() {}); },
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999)),
                  child: Icon(Icons.delete_sweep_outlined, color: Colors.red[400], size: 20)),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              _badge('INFO', const Color(0xFF93C5FD), nInfo),
              const SizedBox(width: 8),
              _badge('OK',   const Color(0xFF22C55E), nOk),
              const SizedBox(width: 8),
              _badge('WARN', const Color(0xFFF59E0B), nWarn),
              const SizedBox(width: 8),
              _badge('ERR',  const Color(0xFFEF4444), nErr),
            ]),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, kNavBarClearance + 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1D2F).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.15)),
                    ),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          border: Border(bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06))),
                        ),
                        child: Row(children: [
                          _dot(const Color(0xFFEF4444)),
                          const SizedBox(width: 6),
                          _dot(const Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          _dot(const Color(0xFF22C55E)),
                          const SizedBox(width: 12),
                          Text('ledsync — system log',
                              style: TextStyle(color: kTextDim, fontSize: 11, fontFamily: 'monospace')),
                          const Spacer(),
                          Text('BAUD: 115200',
                              style: TextStyle(color: kPrimary.withValues(alpha: 0.7),
                                  fontSize: 10, fontFamily: 'monospace')),
                        ]),
                      ),

                      Expanded(
                        child: entries.isEmpty
                            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.terminal, color: kTextDim, size: 40),
                                const SizedBox(height: 12),
                                Text('No system logs yet',
                                    style: TextStyle(color: kTextDim, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('System events will appear here',
                                    style: TextStyle(color: kTextDim.withValues(alpha: 0.6), fontSize: 12)),
                              ]))
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.all(14),
                                itemCount: entries.length,
                                itemBuilder: (_, i) {
                                  final e   = entries[i];
                                  final col = _lvlColor(e.level);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                      Text('[${e.timeStr}] ',
                                          style: TextStyle(color: kTextDim.withValues(alpha: 0.55),
                                              fontSize: 11, fontFamily: 'monospace')),
                                      Text('${_lvlPrefix(e.level)} ',
                                          style: TextStyle(color: col, fontSize: 11,
                                              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                      Expanded(child: Text(e.message,
                                          style: TextStyle(color: col.withValues(alpha: 0.9),
                                              fontSize: 11, fontFamily: 'monospace'))),
                                    ]),
                                  );
                                },
                              ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Row(children: [
                          Text('> ', style: TextStyle(color: kPrimary.withValues(alpha: 0.7),
                              fontSize: 11, fontFamily: 'monospace')),
                          const _BlinkingCursor(),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _badge(String label, Color color, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Text('$label: $count', style: TextStyle(color: color, fontSize: 10,
        fontWeight: FontWeight.w600, fontFamily: 'monospace')),
  );

  Widget _dot(Color c) => Container(width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c));
}

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
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (ctx2, ch2) => Opacity(
      opacity: _ctrl.value > 0.5 ? 1 : 0,
      child: Container(width: 7, height: 13,
          color: const Color(0xFF9e5aed).withValues(alpha: 0.7)),
    ),
  );
}