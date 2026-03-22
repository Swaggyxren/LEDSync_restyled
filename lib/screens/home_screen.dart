import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/main.dart' show
  kCardImageAlignment,
  kCardImageAsset,
  kCardImageOpacity;
import 'package:ledsync/screens/performance_screen.dart';

class _DeviceCache {
  static String? model;
  static String? androidLabel;
  static String? kernel;
  static bool? rooted;
  static bool get ready => model != null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _battery = Battery();
  Timer? _statsTimer;
  late final ScrollController _scrollCtrl;

  double _cpuPct = 0;
  int _ramUsedMb = 0, _ramTotalMb = 0;
  int _battLevel = 0;
  bool _battCharging = false;
  int _prevIdle = 0, _prevTotal = 0;

  String _model        = 'Reading device…';
  String _androidLabel = '';
  String _kernel       = '';
  bool   _rooted       = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _loadDeviceInfo();
    _startStats();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    if (_DeviceCache.ready) {
      if (mounted) {
        setState(() {
          _model        = _DeviceCache.model!;
          _androidLabel = _DeviceCache.androidLabel!;
          _kernel       = _DeviceCache.kernel!;
          _rooted       = _DeviceCache.rooted!;
        });
      }
      return;
    }

    final results = await Future.wait([
      RootLogic.getPhoneInfo(),
      RootLogic.isRooted(),
    ]);
    final info   = results[0] as Map<String, dynamic>;
    final rooted = results[1] as bool;

    final ver = info['version'] as String? ?? '';
    String label = ver;
    if (ver.contains('13')) {
      label = 'Android 13 (Tiramisu)';
    } else if (ver.contains('14')) {
      label = 'Android 14 (Upside Down Cake)';
    } else if (ver.contains('15')) {
      label = 'Android 15 (Vanilla Ice Cream)';
    } else if (ver.contains('16')) {
      label = 'Android 16 (Baklava)';
    }

    _DeviceCache.model        = info['model'] as String? ?? 'Unknown';
    _DeviceCache.androidLabel = label;
    _DeviceCache.kernel       = info['kernel'] as String? ?? '';
    _DeviceCache.rooted       = rooted;

    if (!mounted) return;
    setState(() {
      _model        = _DeviceCache.model!;
      _androidLabel = _DeviceCache.androidLabel!;
      _kernel       = _DeviceCache.kernel!;
      _rooted       = _DeviceCache.rooted!;
    });
  }

  Future<void> _readSysStats() async {
    try {
      final r = await Process.run('su', ['-c', 'cat /proc/stat; echo "---"; cat /proc/meminfo']);
      if (r.exitCode != 0) return;
      final raw   = r.stdout as String;
      final parts = raw.split('---\n');
      if (parts.length < 2) return;
      _parseCpu(parts[0]);
      _parseRam(parts[1]);
    } catch (_) {}
  }

  void _parseCpu(String statRaw) {
    final line = statRaw.split('\n').firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) return;
    final nums  = line.split(RegExp(r'\s+')).skip(1).where((s) => s.isNotEmpty).map(int.parse).toList();
    if (nums.length < 4) return;
    final idle  = nums[3] + (nums.length > 4 ? nums[4] : 0);
    final total = nums.reduce((a, b) => a + b);
    final dI = idle  - _prevIdle;
    final dT = total - _prevTotal;
    _prevIdle  = idle;
    _prevTotal = total;
    if (dT > 0 && mounted) _cpuPct = (1.0 - dI / dT).clamp(0.0, 1.0);
  }

  void _parseRam(String meminfoRaw) {
    int total = 0, avail = 0;
    for (final l in meminfoRaw.split('\n')) {
      final p = l.split(RegExp(r'\s+'));
      if (p.length < 2) continue;
      final v = int.tryParse(p[1]) ?? 0;
      if (l.startsWith('MemTotal:'))     total = v;
      if (l.startsWith('MemAvailable:')) avail = v;
    }
    if (total > 0 && mounted) {
      _ramTotalMb = total ~/ 1024;
      _ramUsedMb  = (total - avail) ~/ 1024;
    }
  }

  Future<void> _updateBattery() async {
    try {
      final res     = await Future.wait([_battery.batteryLevel, _battery.batteryState]);
      final level   = res[0] as int;
      final state   = res[1] as BatteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;
      if (!mounted) return;
      if (_battLevel != level || _battCharging != charging) {
        setState(() {
          _battLevel    = level;
          _battCharging = charging;
        });
      }
    } catch (_) {}
  }

  Future<void> _seedCpu() async {
    try {
      final r = await Process.run('su', ['-c', 'head -1 /proc/stat']);
      if (r.exitCode != 0) return;
      final line = (r.stdout as String).trim();
      final nums = line.split(RegExp(r'\s+')).skip(1).where((s) => s.isNotEmpty).map(int.parse).toList();
      if (nums.length < 4) return;
      _prevIdle  = nums[3] + (nums.length > 4 ? nums[4] : 0);
      _prevTotal = nums.reduce((a, b) => a + b);
    } catch (_) {}
  }

  void _startStats() {
    _seedCpu().then((_) {
      _readSysStats();
      _updateBattery();
      _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await Future.wait([_readSysStats(), _updateBattery()]);
        if (mounted) { setState(() {}); }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final topPad  = MediaQuery.of(context).padding.top;
    final cpuLabel = '${(_cpuPct * 100).toStringAsFixed(0)}%';
    final ramLabel = _ramTotalMb > 0
        ? '${(_ramUsedMb / 1024).toStringAsFixed(1)} GB / ${(_ramTotalMb / 1024).toStringAsFixed(1)} GB'
        : 'Reading…';
    final ramFrac = _ramTotalMb > 0 ? (_ramUsedMb / _ramTotalMb).clamp(0.0, 1.0) : 0.0;
    final battStr = _battLevel > 0
        ? '$_battLevel% • ${_battCharging ? 'Charging' : 'Discharging'}'
        : 'Reading…';

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(children: [
        SingleChildScrollView(
          controller: _scrollCtrl,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, topPad + 64, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _deviceCard(cs),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _StatCard(
                  icon: _battCharging
                      ? Icons.battery_charging_full_rounded
                      : Icons.battery_std_rounded,
                  iconColor: _battCharging ? cs.tertiary : cs.primary,
                  iconBg: _battCharging
                      ? cs.tertiaryContainer
                      : cs.primaryContainer,
                  title: 'Battery',
                  sub: battStr,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.lightbulb_rounded,
                  iconColor: cs.secondary,
                  iconBg: cs.secondaryContainer,
                  title: 'LED Engine',
                  sub: 'Active',
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'System Performance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurface, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, a1, a2) => PerformanceScreen(
                        initialCpu:      _cpuPct,
                        initialRamUsed:  _ramUsedMb,
                        initialRamTotal: _ramTotalMb,
                        initialBatt:     _battLevel,
                        initialCharging: _battCharging,
                      ),
                      transitionsBuilder: (_, a1, a2, child) => SlideTransition(
                        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                            .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    ),
                  ),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PerformanceSummaryCard(
              cpuPct:   _cpuPct,
              ramFrac:  ramFrac,
              cpuLabel: cpuLabel,
              ramLabel: ramLabel,
            ),
            const SizedBox(height: 20),
            Row(children: [
              Text("Xi'annnnnn/@kasajin001",
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              const Spacer(),
              Text('Initial Release – Expect Bugs',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
            ]),
          ]),
        ),

        // ── Top app bar ────────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            color: cs.surface,
            padding: EdgeInsets.only(
              left: 20, right: 12, top: topPad + 4, bottom: 8),
            child: Row(children: [
              Text(
                'LED Sync',
                style: GoogleFonts.spaceGrotesk(
                  color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: Icon(Icons.settings_outlined, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _deviceCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Hero image area
        SizedBox(
          height: 164,
          child: Stack(fit: StackFit.expand, children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.7),
                    cs.surfaceContainerHigh,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Opacity(
              opacity: kCardImageOpacity,
              child: Align(
                alignment: kCardImageAlignment,
                child: Image.asset(
                  kCardImageAsset,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            // Bottom fade into card surface
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, cs.surfaceContainerHigh],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
            ),
          ]),
        ),
        // Device info
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _model,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: cs.onSurface, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(_androidLabel,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            if (_kernel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(_kernel,
                  style: TextStyle(color: cs.outline, fontSize: 10, fontFamily: 'monospace'),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 14),
            Row(children: [
              _PulseDot(rooted: _rooted),
              const SizedBox(width: 8),
              Text('Root Status: ',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              Text(
                _rooted ? 'ACTIVE' : 'INACTIVE',
                style: TextStyle(
                  color: _rooted ? cs.primary : cs.error,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─── Pulsing root status dot ─────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  final bool rooted;
  const _PulseDot({required this.rooted});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final dot = widget.rooted ? cs.primary : cs.error;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dot,
          boxShadow: [
            BoxShadow(
              color: dot.withValues(alpha: 0.6 * _ctrl.value),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat card ───────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final Color iconBg, iconColor;
  final IconData icon;
  final String title, sub;
  const _StatCard({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.onSurface, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ─── Performance summary card ─────────────────────────────────────────────
class _PerformanceSummaryCard extends StatelessWidget {
  final double cpuPct, ramFrac;
  final String cpuLabel, ramLabel;
  const _PerformanceSummaryCard({
    required this.cpuPct,
    required this.ramFrac,
    required this.cpuLabel,
    required this.ramLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          _Bar(label: 'CPU Usage', val: cpuLabel, prog: cpuPct, color: cs.primary),
          const SizedBox(height: 20),
          _Bar(label: 'RAM Usage', val: ramLabel, prog: ramFrac, color: cs.tertiary),
        ]),
      ),
    );
  }
}

// ─── Progress bar ────────────────────────────────────────────────────────
class _Bar extends StatelessWidget {
  final String label, val;
  final double prog;
  final Color color;
  const _Bar({required this.label, required this.val, required this.prog, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        Text(val, style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      TweenAnimationBuilder<double>(
        tween: Tween(end: prog.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, fill, _) => SizedBox(
          height: 6,
          width: double.infinity,
          child: CustomPaint(painter: _BarPainter(fill: fill, color: color, trackColor: cs.outlineVariant)),
        ),
      ),
    ]);
  }
}

class _BarPainter extends CustomPainter {
  final double fill;
  final Color color, trackColor;
  const _BarPainter({required this.fill, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(99);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), r),
      Paint()..color = trackColor.withValues(alpha: 0.4),
    );
    if (fill <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * fill, size.height), r),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fill != fill || old.color != color || old.trackColor != trackColor;
}
