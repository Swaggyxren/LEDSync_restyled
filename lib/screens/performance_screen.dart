import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Performance Monitor Screen ───────────────────────────────────────────
// Opens with pre-seeded values from HomeScreen — no blank loading state.
// Warm-up phase: 500ms × 8 ticks to fill the sparkline, then settles to 2s.
class PerformanceScreen extends StatefulWidget {
  final double initialCpu;
  final int    initialRamUsed, initialRamTotal;
  final int    initialBatt;
  final bool   initialCharging;

  const PerformanceScreen({
    super.key,
    this.initialCpu      = 0,
    this.initialRamUsed  = 0,
    this.initialRamTotal = 0,
    this.initialBatt     = 0,
    this.initialCharging = false,
  });

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen>
    with SingleTickerProviderStateMixin {

  // ── History ───────────────────────────────────────────────────────────
  static const _histLen = 60;
  final List<double> _cpuHistory = [];

  // ── Live values ───────────────────────────────────────────────────────
  double _cpuPct    = 0;
  int    _ramUsed   = 0, _ramTotal = 0;
  int    _battLevel = 0;
  bool   _charging  = false;

  // ── Proc stat baseline ────────────────────────────────────────────────
  int _prevIdle = 0, _prevTotal = 0;

  // ── Warm-up state ─────────────────────────────────────────────────────
  int  _warmTicks  = 0;
  static const _warmCount = 8;
  static const _warmMs    = 500;
  static const _steadyMs  = 2000;
  bool get _isWarming => _warmTicks < _warmCount;

  Timer? _timer;

  // ── Live-dot animation ────────────────────────────────────────────────
  late AnimationController _dotAnim;

  @override
  void initState() {
    super.initState();

    _dotAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    // Pre-seed from caller's values — instant display, no blank state
    _cpuPct    = widget.initialCpu;
    _ramUsed   = widget.initialRamUsed;
    _ramTotal  = widget.initialRamTotal;
    _battLevel = widget.initialBatt;
    _charging  = widget.initialCharging;

    // Pre-fill history so graph isn't empty on open
    for (int i = 0; i < _histLen; i++) { _cpuHistory.add(_cpuPct); }

    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dotAnim.dispose();
    super.dispose();
  }

  // ── Polling ───────────────────────────────────────────────────────────
  void _startPolling() {
    _seedCpuBaseline().then((_) {
      _tick();
      _scheduleNext();
    });
  }

  void _scheduleNext() {
    final ms = _isWarming ? _warmMs : _steadyMs;
    _timer = Timer(Duration(milliseconds: ms), () async {
      await _tick();
      if (mounted) _scheduleNext();
    });
  }

  Future<void> _seedCpuBaseline() async {
    try {
      final r = await Process.run('su', ['-c', 'head -1 /proc/stat']);
      if (r.exitCode != 0) return;
      final nums = (r.stdout as String).trim()
          .split(RegExp(r'\s+')).skip(1)
          .where((s) => s.isNotEmpty).map(int.parse).toList();
      if (nums.length < 4) return;
      _prevIdle  = nums[3] + (nums.length > 4 ? nums[4] : 0);
      _prevTotal = nums.reduce((a, b) => a + b);
    } catch (_) {}
  }

  Future<void> _tick() async {
    try {
      final r = await Process.run('su', ['-c',
        'cat /proc/stat; echo "---"; cat /proc/meminfo']);
      if (r.exitCode != 0) return;
      final parts = (r.stdout as String).split('---\n');
      if (parts.length < 2) return;
      _parseCpu(parts[0]);
      _parseRam(parts[1]);
    } catch (_) {}

    if (_isWarming) _warmTicks++;
    if (mounted) setState(() {});
  }

  void _parseCpu(String raw) {
    final line = raw.split('\n').firstWhere(
        (l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) return;
    final nums = line.split(RegExp(r'\s+')).skip(1)
        .where((s) => s.isNotEmpty).map(int.parse).toList();
    if (nums.length < 4) return;
    final idle  = nums[3] + (nums.length > 4 ? nums[4] : 0);
    final total = nums.reduce((a, b) => a + b);
    final dI    = idle  - _prevIdle;
    final dT    = total - _prevTotal;
    _prevIdle  = idle;
    _prevTotal = total;
    if (dT > 0) {
      _cpuPct = (1.0 - dI / dT).clamp(0.0, 1.0);
      _cpuHistory.add(_cpuPct);
      if (_cpuHistory.length > _histLen) _cpuHistory.removeAt(0);
    }
  }

  void _parseRam(String raw) {
    int total = 0, avail = 0;
    for (final l in raw.split('\n')) {
      final p = l.split(RegExp(r'\s+'));
      if (p.length < 2) continue;
      final v = int.tryParse(p[1]) ?? 0;
      if (l.startsWith('MemTotal:'))     total = v;
      if (l.startsWith('MemAvailable:')) avail = v;
    }
    if (total > 0) {
      _ramTotal = total ~/ 1024;
      _ramUsed  = (total - avail) ~/ 1024;
    }
  }

  // ── Color helpers ─────────────────────────────────────────────────────
  Color _cpuColor(ColorScheme cs) {
    if (_cpuPct > 0.85) return cs.error;
    if (_cpuPct > 0.60) return Colors.orange;
    return cs.primary;
  }

  Color _battColor(ColorScheme cs) {
    if (_charging)       return cs.tertiary;
    if (_battLevel < 20) return cs.error;
    if (_battLevel < 40) return Colors.orange;
    return cs.primary;
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final cpuCol  = _cpuColor(cs);
    final battCol = _battColor(cs);

    final cpuPct   = (_cpuPct * 100).toStringAsFixed(1);
    final ramFrac  = _ramTotal > 0 ? (_ramUsed / _ramTotal).clamp(0.0, 1.0) : 0.0;
    final ramUsedG = (_ramUsed                       / 1024).toStringAsFixed(1);
    final ramTotG  = (_ramTotal                      / 1024).toStringAsFixed(1);
    final ramFreeG = ((_ramTotal - _ramUsed)         / 1024).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(children: [
          // ── App bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              Text('Performance Monitor',
                  style: GoogleFonts.spaceGrotesk(
                    color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              // Live dot indicator
              AnimatedBuilder(
                animation: _dotAnim,
                builder: (_, _) {
                  final dotColor = _isWarming ? Colors.orange : cs.tertiary;
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        boxShadow: [BoxShadow(
                          color: dotColor.withValues(alpha: _dotAnim.value * 0.7),
                          blurRadius: 8, spreadRadius: 2)],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isWarming ? 'SAMPLING' : 'LIVE',
                      style: TextStyle(
                        color: dotColor, fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace', letterSpacing: 1.2),
                    ),
                  ]);
                },
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // ── Metric cards ───────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(children: [

                // ── CPU card ─────────────────────────────────────────────
                _metricCard(
                  cs: cs,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Label row
                    Row(children: [
                      _labelChip('CPU', cpuCol, cs),
                      const Spacer(),
                      Text('${_isWarming ? _warmMs : _steadyMs}ms interval',
                          style: TextStyle(
                            color: cs.outline, fontSize: 10, fontFamily: 'monospace')),
                    ]),
                    const SizedBox(height: 12),
                    // Big number + stats
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(cpuPct,
                          style: GoogleFonts.spaceGrotesk(
                            color: cpuCol, fontSize: 52,
                            fontWeight: FontWeight.bold, height: 1.0)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        child: Text('%',
                            style: TextStyle(
                              color: cpuCol.withValues(alpha: 0.7),
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('MAX', style: TextStyle(color: cs.outline, fontSize: 9, letterSpacing: 1.2)),
                        Text(
                          '${(_cpuHistory.isEmpty ? 0 : _cpuHistory.reduce(math.max) * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('AVG', style: TextStyle(color: cs.outline, fontSize: 9, letterSpacing: 1.2)),
                        Text(
                          '${(_cpuHistory.isEmpty ? 0 : _cpuHistory.reduce((a, b) => a + b) / _cpuHistory.length * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                    const SizedBox(height: 16),
                    // Sparkline
                    SizedBox(
                      height: 90,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          data:       _cpuHistory,
                          color:      cpuCol,
                          gridColor:  cs.outlineVariant.withValues(alpha: 0.3),
                          isWarming:  _isWarming,
                        ),
                        size: const Size(double.infinity, 90),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('${_histLen}s history',
                          style: TextStyle(color: cs.outline, fontSize: 9, fontFamily: 'monospace')),
                      const Spacer(),
                      Text('now →',
                          style: TextStyle(color: cs.outline, fontSize: 9, fontFamily: 'monospace')),
                    ]),
                  ]),
                ),

                const SizedBox(height: 12),

                // ── RAM card ──────────────────────────────────────────────
                _metricCard(
                  cs: cs,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _labelChip('RAM', cs.secondary, cs),
                      const Spacer(),
                      Text('$ramFreeG GB free',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                    ]),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(ramUsedG,
                          style: GoogleFonts.spaceGrotesk(
                            color: cs.secondary, fontSize: 44,
                            fontWeight: FontWeight.bold, height: 1.0)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 4),
                        child: Text('GB',
                            style: TextStyle(color: cs.secondary, fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 8),
                        child: Text('/ $ramTotG GB',
                            style: TextStyle(color: cs.outline, fontSize: 14)),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    // Segmented bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Stack(children: [
                        Container(height: 12, color: cs.surfaceContainerHighest),
                        FractionallySizedBox(
                          widthFactor: ramFrac.clamp(0.0, 1.0),
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              gradient: LinearGradient(
                                colors: [
                                  cs.secondary,
                                  ramFrac > 0.85 ? cs.error
                                      : ramFrac > 0.65 ? Colors.orange
                                      : cs.secondary,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      _ramChip(cs, 'Used',  ramUsedG, cs.secondary),
                      const SizedBox(width: 8),
                      _ramChip(cs, 'Free',  ramFreeG, cs.tertiary),
                      const SizedBox(width: 8),
                      _ramChip(cs, 'Total', ramTotG,  cs.onSurfaceVariant),
                    ]),
                  ]),
                ),

                const SizedBox(height: 12),

                // ── Battery card ──────────────────────────────────────────
                _metricCard(
                  cs: cs,
                  child: Row(children: [
                    // Ring
                    SizedBox(
                      width: 110, height: 110,
                      child: CustomPaint(
                        painter: _RingPainter(
                          progress:   _battLevel / 100.0,
                          color:      battCol,
                          trackColor: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              _charging ? Icons.bolt_rounded
                                  : _battLevel < 20 ? Icons.battery_alert_rounded
                                  : Icons.battery_std_rounded,
                              color: battCol, size: 18),
                            Text('$_battLevel%',
                                style: TextStyle(
                                  color: battCol, fontSize: 18, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _labelChip('BATTERY', battCol, cs),
                        const SizedBox(height: 12),
                        Text(
                          _charging ? 'Charging' : 'Discharging',
                          style: GoogleFonts.spaceGrotesk(
                            color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _battLevel >= 80 ? 'Battery health: Good'
                              : _battLevel >= 40 ? 'Moderate level'
                              : _battLevel >= 20 ? 'Low — consider charging'
                              : 'Critical — charge now',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: Stack(children: [
                            Container(height: 6, color: cs.surfaceContainerHighest),
                            FractionallySizedBox(
                              widthFactor: (_battLevel / 100.0).clamp(0.0, 1.0),
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: battCol,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 10),
                Text(
                  'Data sourced from /proc/stat · /proc/meminfo · battery_plus',
                  style: TextStyle(
                    color: cs.outline.withValues(alpha: 0.5),
                    fontSize: 9, fontFamily: 'monospace'),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────
  Widget _metricCard({required ColorScheme cs, required Widget child}) => Card(
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      );

  Widget _labelChip(String label, Color color, ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
              color: color, fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      );

  Widget _ramChip(ColorScheme cs, String label, String val, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(color: cs.outline, fontSize: 9, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text('$val GB',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

// ─── Sparkline painter ────────────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color        color;
  final Color        gridColor;
  final bool         isWarming;

  const _SparklinePainter({
    required this.data,
    required this.color,
    required this.gridColor,
    required this.isWarming,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final w = size.width, h = size.height;

    // Grid lines
    final gridPaint = Paint()..color = gridColor..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = h * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Build path
    final path = Path(), fill = Path();
    for (int i = 0; i < data.length; i++) {
      final x = w * i / (data.length - 1);
      final y = h * (1.0 - data[i]);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, h);
        fill.lineTo(x, y);
      } else {
        final prev = Offset(w * (i - 1) / (data.length - 1), h * (1.0 - data[i - 1]));
        final cpx  = (prev.dx + x) / 2;
        path.cubicTo(cpx, prev.dy, cpx, y, x, y);
        fill.cubicTo(cpx, prev.dy, cpx, y, x, y);
      }
    }
    fill.lineTo(w, h);
    fill.close();

    // Gradient fill
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: isWarming ? 0.25 : 0.18),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill,
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: isWarming ? 0.6 : 0.9)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Live dot at end
    if (data.isNotEmpty) {
      final lastX = w, lastY = h * (1.0 - data.last);
      canvas.drawCircle(Offset(lastX, lastY), 4.5, Paint()..color = color);
      canvas.drawCircle(Offset(lastX, lastY), 4.5,
          Paint()..color = color.withValues(alpha: 0.3)..strokeWidth = 3..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data != data || old.isWarming != isWarming || old.color != color;
}

// ─── Ring painter ─────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color  color, trackColor;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c  = Offset(size.width / 2, size.height / 2);
    final r  = (size.width / 2) - 8;
    const sw = 7.0;

    canvas.drawCircle(c, r,
        Paint()..color = trackColor..style = PaintingStyle.stroke..strokeWidth = sw);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
