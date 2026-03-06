import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/main.dart' show
  glassDecoration,
  kCardImageAlignment,
  kCardImageAsset,
  kCardImageOpacity,
  kNavBarClearance,
  kNavyEnd,
  kNavyStart,
  kPrimary,
  kTextDim,
  kTextMuted;
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

  String _model = 'Reading device…';
  String _androidLabel = '';
  String _kernel = '';
  bool _rooted = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(() {
      if (mounted) setState(() {});
    });
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
      setState(() {
        _model = _DeviceCache.model!;
        _androidLabel = _DeviceCache.androidLabel!;
        _kernel = _DeviceCache.kernel!;
        _rooted = _DeviceCache.rooted!;
      });
      return;
    }

    final results = await Future.wait([
      RootLogic.getPhoneInfo(),
      RootLogic.isRooted(),
    ]);
    final info = results[0] as Map<String, dynamic>;
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

    _DeviceCache.model = info['model'] as String? ?? 'Unknown';
    _DeviceCache.androidLabel = label;
    _DeviceCache.kernel = info['kernel'] as String? ?? '';
    _DeviceCache.rooted = rooted;

    if (!mounted) return;
    setState(() {
      _model = _DeviceCache.model!;
      _androidLabel = _DeviceCache.androidLabel!;
      _kernel = _DeviceCache.kernel!;
      _rooted = _DeviceCache.rooted!;
    });
  }

  Future<void> _readSysStats() async {
    try {
      final r = await Process.run('su', ['-c', 'cat /proc/stat; echo "---"; cat /proc/meminfo']);
      if (r.exitCode != 0) return;

      final raw = r.stdout as String;
      final parts = raw.split('---\n');
      if (parts.length < 2) return;

      _parseCpu(parts[0]);
      _parseRam(parts[1]);
    } catch (_) {}
  }

  void _parseCpu(String statRaw) {
    final line = statRaw.split('\n').firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) return;
    final nums = line.split(RegExp(r'\s+')).skip(1).where((s) => s.isNotEmpty).map(int.parse).toList();
    if (nums.length < 4) return;

    final idle = nums[3] + (nums.length > 4 ? nums[4] : 0);
    final total = nums.reduce((a, b) => a + b);
    final dI = idle - _prevIdle;
    final dT = total - _prevTotal;
    _prevIdle = idle;
    _prevTotal = total;

    if (dT > 0 && mounted) {
      _cpuPct = (1.0 - dI / dT).clamp(0.0, 1.0);
    }
  }

  void _parseRam(String meminfoRaw) {
    int total = 0, avail = 0;
    for (final l in meminfoRaw.split('\n')) {
      final p = l.split(RegExp(r'\s+'));
      if (p.length < 2) continue;
      final v = int.tryParse(p[1]) ?? 0;
      if (l.startsWith('MemTotal:')) total = v;
      if (l.startsWith('MemAvailable:')) avail = v;
    }
    if (total > 0 && mounted) {
      _ramTotalMb = total ~/ 1024;
      _ramUsedMb = (total - avail) ~/ 1024;
    }
  }

  Future<void> _updateBattery() async {
    try {
      final res = await Future.wait([
        _battery.batteryLevel,
        _battery.batteryState,
      ]);
      final level = res[0] as int;
      final state = res[1] as BatteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;
      if (!mounted) return;
      if (_battLevel != level || _battCharging != charging) {
        setState(() {
          _battLevel = level;
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
      _prevIdle = nums[3] + (nums.length > 4 ? nums[4] : 0);
      _prevTotal = nums.reduce((a, b) => a + b);
    } catch (_) {}
  }

  void _startStats() {
    _seedCpu().then((_) {
      _readSysStats();
      _updateBattery();
      _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await Future.wait([_readSysStats(), _updateBattery()]);
        if (mounted) setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final cpuLabel = '${(_cpuPct * 100).toStringAsFixed(0)}%';
    final ramLabel = _ramTotalMb > 0
        ? '${(_ramUsedMb / 1024).toStringAsFixed(1)} GB / ${(_ramTotalMb / 1024).toStringAsFixed(1)} GB'
        : 'Reading…';
    final ramFrac = _ramTotalMb > 0 ? (_ramUsedMb / _ramTotalMb).clamp(0.0, 1.0) : 0.0;
    final battStr = _battLevel > 0 ? '$_battLevel% • ${_battCharging ? 'Charging' : 'Discharging'}' : 'Reading…';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kNavyStart, kNavyEnd],
        ),
      ),
      child: Stack(children: [
        _Glow(color: kPrimary.withValues(alpha: 0.15), size: 240, top: -80, right: -80),
        _Glow(
          color: const Color(0xFF2563EB).withValues(alpha: 0.07),
          size: 280,
          top: MediaQuery.of(context).size.height * 0.45,
          left: -100,
        ),
        Positioned.fill(
          child: Stack(children: [
            SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, topPad + 56, 24, kNavBarClearance + 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _deviceCard(),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: _StatCard(
                      iconBg: kPrimary.withValues(alpha: 0.2),
                      iconColor: kPrimary,
                      icon: _battCharging ? Icons.battery_charging_full : Icons.battery_std,
                      title: 'Battery',
                      sub: battStr,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: _StatCard(
                      iconBg: Color(0x333B82F6),
                      iconColor: Color(0xFF60A5FA),
                      icon: Icons.lightbulb_outline_rounded,
                      title: 'LED Engine',
                      sub: 'Active',
                    ),
                  ),
                ]),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    'System Performance',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, a1, a2) => PerformanceScreen(
                          initialCpu: _cpuPct,
                          initialRamUsed: _ramUsedMb,
                          initialRamTotal: _ramTotalMb,
                          initialBatt: _battLevel,
                          initialCharging: _battCharging,
                        ),
                        transitionsBuilder: (_, a1, a2, child) => SlideTransition(
                          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                              .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                      ),
                    ),
                    child: const Text('View All', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 14),
                _PerformanceSummaryCard(
                  cpuPct: _cpuPct,
                  ramFrac: ramFrac,
                  cpuLabel: cpuLabel,
                  ramLabel: ramLabel,
                ),
                const SizedBox(height: 20),
                Row(children: [
                  const Text("Xi'annnnnn/@kasajin001", style: TextStyle(fontSize: 11, color: kTextDim)),
                  const Spacer(),
                  const Text('Initial Release – Expect Bugs', style: TextStyle(fontSize: 11, color: kTextDim)),
                ]),
              ]),
            ),
            Positioned(top: 0, left: 0, right: 0, height: topPad + 160, child: const IgnorePointer(child: _HeaderFade())),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.only(left: 20, right: 20, top: topPad + 8, bottom: 10),
                child: Row(children: [
                  Text(
                    'LED Sync',
                    style: GoogleFonts.spaceGrotesk(color: kTextMuted, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const Spacer(),
                  const _GlassBtn(icon: Icons.settings_outlined),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _deviceCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: glassDecoration(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 170,
              child: Stack(fit: StackFit.expand, children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F1D2F), Color(0xFF1a1440)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                  child: Opacity(
                    opacity: kCardImageOpacity,
                    child: Align(
                      alignment: kCardImageAlignment,
                      child: Image.asset(
                        kCardImageAsset,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD90A1628)],
                        stops: [0.35, 1.0],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _model,
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFFD4DCE6),
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_androidLabel, style: const TextStyle(color: kTextMuted, fontSize: 15)),
                if (_kernel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _kernel,
                    style: const TextStyle(color: kTextDim, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  _PulseDot(rooted: _rooted),
                  const SizedBox(width: 8),
                  const Text('Root Status: ', style: TextStyle(color: kTextMuted, fontWeight: FontWeight.w500, fontSize: 13)),
                  Text(
                    _rooted ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      color: _rooted ? const Color(0xFF60A5FA) : Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HeaderFade extends StatelessWidget {
  const _HeaderFade();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              kNavyStart,
              Color(0xF50A1628),
              Color(0xD10A1628),
              Color(0x990A1628),
              Color(0x610A1628),
              Color(0x2E0A1628),
              Color(0x0F0A1628),
              Color(0x000A1628),
            ],
            stops: [0.0, 0.12, 0.28, 0.50, 0.68, 0.82, 0.92, 1.0],
          ),
        ),
      );
}

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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.rooted ? const Color(0xFF3B82F6) : Colors.red;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dotColor,
          boxShadow: [
            BoxShadow(
              color: dotColor.withValues(alpha: 0.65),
              blurRadius: _ctrl.value * 12,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: glassDecoration(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 16),
              Text(title, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: kTextMuted, fontSize: 12)),
            ]),
          ),
        ),
      );
}

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
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: glassDecoration(),
            child: Column(children: [
              _Bar(label: 'CPU Usage', val: cpuLabel, prog: cpuPct, color: kPrimary),
              const SizedBox(height: 22),
              _Bar(label: 'RAM Usage', val: ramLabel, prog: ramFrac, color: const Color(0xFF3B82F6)),
            ]),
          ),
        ),
      );
}

class _Bar extends StatelessWidget {
  final String label, val;
  final double prog;
  final Color color;
  const _Bar({required this.label, required this.val, required this.prog, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: kTextMuted, fontSize: 12)),
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(end: prog.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, fill, __) => SizedBox(
            height: 6,
            width: double.infinity,
            child: CustomPaint(painter: _BarPainter(fill: fill, color: color)),
          ),
        ),
      ]);
}

class _BarPainter extends CustomPainter {
  final double fill;
  final Color color;
  const _BarPainter({required this.fill, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(99);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), r),
      Paint()..color = Colors.white.withValues(alpha: 0.09),
    );
    if (fill <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * fill, size.height), r),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.fill != fill || old.color != color;
}

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  const _GlassBtn({required this.icon});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(width: 42, height: 42, decoration: glassDecoration(radius: 999), child: Icon(icon, color: kTextMuted, size: 22)),
        ),
      );
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  final double? top, left, right;
  const _Glow({required this.color, required this.size, this.top, this.left, this.right});

  @override
  Widget build(BuildContext context) => Positioned(
        top: top,
        left: left,
        right: right,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 40)],
            ),
          ),
        ),
      );
}
