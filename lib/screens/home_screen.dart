import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/core/notif_permission.dart';
import 'package:ledsync/core/system_stats_parser.dart';
import 'package:ledsync/main.dart'
    show kCardImageAlignment, kCardImageAsset, kCardImageOpacity;
import 'package:ledsync/models/devices/device_config.dart';
import 'package:ledsync/screens/performance_screen.dart';
import 'package:ledsync/widgets/shimmer_loading.dart';

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

  // ── First-launch settings tooltip ────────────────────────────────────────
  static const _kTooltipShown = 'settings_tooltip_shown';
  final _settingsKey = GlobalKey();
  OverlayEntry? _tooltipOverlay;
  Timer? _tooltipTimer;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _loadDeviceInfo();
    _startStats();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTooltip());
  }

  @override
  void dispose() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
    _tooltipTimer?.cancel();
    _statsTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    if (_DeviceCache.ready) {
      if (mounted) {
        setState(() {
          _model = _DeviceCache.model!;
          _androidLabel = _DeviceCache.androidLabel!;
          _kernel = _DeviceCache.kernel!;
          _rooted = _DeviceCache.rooted!;
        });
      }
      return;
    }

    final results = await Future.wait([
      RootLogic.getPhoneInfo(),
      RootLogic.isRooted(),
    ]);
    final info = results[0] as Map<String, dynamic>;
    final rooted = results[1] as bool;

    final ver = info['version'] as String? ?? '';
    // Manual codename map — update periodically as new Android versions release.
    // androidInfo.version.codename is empty for stable releases, so this is needed.
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
      final r = await Process.run('su', [
        '-c',
        'cat /proc/stat; echo "---"; cat /proc/meminfo',
      ]);
      if (r.exitCode != 0) return;
      final raw = r.stdout as String;
      final parts = raw.split('---\n');
      if (parts.length < 2) return;
      _parseCpu(parts[0]);
      _parseRam(parts[1]);
    } catch (_) {}
  }

  void _parseCpu(String statRaw) {
    final result = SystemStatsParser.parseCpu(statRaw, _prevIdle, _prevTotal);
    _prevIdle = result.prevIdle;
    _prevTotal = result.prevTotal;
    if (result.cpuPct > 0 && mounted) _cpuPct = result.cpuPct;
  }

  void _parseRam(String meminfoRaw) {
    final result = SystemStatsParser.parseRam(meminfoRaw);
    if (result.totalMb > 0 && mounted) {
      _ramTotalMb = result.totalMb;
      _ramUsedMb = result.usedMb;
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
      final charging =
          state == BatteryState.charging || state == BatteryState.full;
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
      final nums = line
          .split(RegExp(r'\s+'))
          .skip(1)
          .where((s) => s.isNotEmpty)
          .map(int.parse)
          .toList();
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
        if (mounted) {
          setState(() {});
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    final cpuLabel = '${(_cpuPct * 100).toStringAsFixed(0)}%';
    final ramLabel = _ramTotalMb > 0
        ? '${(_ramUsedMb / 1024).toStringAsFixed(1)} GB / ${(_ramTotalMb / 1024).toStringAsFixed(1)} GB'
        : 'Reading…';
    final ramFrac = _ramTotalMb > 0
        ? (_ramUsedMb / _ramTotalMb).clamp(0.0, 1.0)
        : 0.0;
    final battStr = _battLevel > 0
        ? '$_battLevel% • ${_battCharging ? 'Charging' : 'Discharging'}'
        : 'Reading…';

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollCtrl,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, topPad + 64, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _deviceCard(cs),
                const SizedBox(height: 16),
                Row(
                  children: [
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
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'System Performance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, a1, a2) => PerformanceScreen(
                            initialCpu: _cpuPct,
                            initialRamUsed: _ramUsedMb,
                            initialRamTotal: _ramTotalMb,
                            initialBatt: _battLevel,
                            initialCharging: _battCharging,
                          ),
                          transitionsBuilder: (_, a1, a2, child) =>
                              SlideTransition(
                                position:
                                    Tween(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: a1,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
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
                  cpuPct: _cpuPct,
                  ramFrac: ramFrac,
                  cpuLabel: cpuLabel,
                  ramLabel: ramLabel,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      "Xi'annnnnn/@kasajin001",
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                    const Spacer(),
                    Text(
                      'Initial Release – Expect Bugs',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Top app bar ────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: cs.surface,
              padding: EdgeInsets.only(
                left: 20,
                right: 12,
                top: topPad + 4,
                bottom: 8,
              ),
              child: Row(
                children: [
                  Text(
                    'LED Sync',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: _settingsKey,
                    onPressed: () => _showDevicePicker(context, cs),
                    icon: Icon(
                      Icons.settings_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image area
          SizedBox(
            height: 164,
            child: Stack(
              fit: StackFit.expand,
              children: [
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
              ],
            ),
          ),
          // Device info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_DeviceCache.ready) ...[
                  Text(
                    _model,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _androidLabel,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                  ),
                  if (_kernel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _kernel,
                      style: TextStyle(
                        color: cs.outline,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else ...[
                  const ShimmerBox(width: 200, height: 28, borderRadius: 8),
                  const SizedBox(height: 8),
                  const ShimmerBox(width: 140, height: 16, borderRadius: 6),
                  const SizedBox(height: 6),
                  const ShimmerBox(width: 260, height: 12, borderRadius: 6),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    _PulseDot(rooted: _rooted),
                    const SizedBox(width: 8),
                    Text(
                      'Root Status: ',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _rooted ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                        color: _rooted ? cs.primary : cs.error,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── First-launch settings tooltip ────────────────────────────────────────

  Future<void> _maybeShowTooltip() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_kTooltipShown) ?? false;
    if (shown || !mounted) return;

    // Wait until notification listener is granted before showing the tooltip
    // so it doesn't appear under/before the permission dialogs.
    final completer = Completer<void>();
    int elapsed = 0;
    _tooltipTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      elapsed += 2000;
      if (!mounted || await NotifPermission.isEnabled() || elapsed >= 30000) {
        t.cancel();
        _tooltipTimer = null;
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;
    if (!mounted) return;
    if (!await NotifPermission.isEnabled()) return; // never granted — skip

    await prefs.setBool(_kTooltipShown, true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _showSettingsTooltip();
  }

  void _showSettingsTooltip() {
    final ctx = _settingsKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final cs = Theme.of(context).colorScheme;

    _tooltipOverlay = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _tooltipOverlay?.remove();
          _tooltipOverlay = null;
        },
        child: Stack(
          children: [
            // Scrim
            Container(color: Colors.black.withValues(alpha: 0.45)),
            // Tooltip bubble — positioned below the settings icon
            Positioned(
              right: 12,
              top: pos.dy + size.height + 6,
              child: GestureDetector(
                onTap: () {}, // block scrim tap through bubble
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Arrow pointing up-right at the icon
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: 12,
                              bottom: 4,
                            ),
                            child: Icon(
                              Icons.arrow_drop_up_rounded,
                              color: cs.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                        ),
                        Text(
                          'Select your device',
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap the settings icon to choose your device config so LED patterns work correctly.',
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            color: cs.onPrimaryContainer.withValues(
                              alpha: 0.85,
                            ),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            _tooltipOverlay?.remove();
                            _tooltipOverlay = null;
                          },
                          child: Text(
                            'Got it',
                            style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(_tooltipOverlay!);
  }

  // ── Device picker ─────────────────────────────────────────────────────────

  Future<void> _showDevicePicker(BuildContext ctx, ColorScheme cs) async {
    final current = RootLogic.activeConfig;
    DeviceConfig? selected = current;

    await showDialog<void>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Select device',
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: RootLogic.allConfigs.map((cfg) {
              final isSelected = selected?.deviceName == cfg.deviceName;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => selected = cfg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? cs.primary : cs.outline,
                            width: isSelected ? 6 : 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          cfg.deviceName,
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            color: cs.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            FilledButton(
              onPressed: () {
                if (selected != null) {
                  RootLogic.setConfig(selected!);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Device set to ${selected!.deviceName}'),
                    ),
                  );
                }
                Navigator.pop(dctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
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

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dot = widget.rooted ? cs.primary : cs.error;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 10,
        height: 10,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
        child: Column(
          children: [
            _Bar(
              label: 'CPU Usage',
              val: cpuLabel,
              prog: cpuPct,
              color: cs.primary,
            ),
            const SizedBox(height: 20),
            _Bar(
              label: 'RAM Usage',
              val: ramLabel,
              prog: ramFrac,
              color: cs.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress bar ────────────────────────────────────────────────────────
class _Bar extends StatelessWidget {
  final String label, val;
  final double prog;
  final Color color;
  const _Bar({
    required this.label,
    required this.val,
    required this.prog,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            Text(
              val,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(end: prog.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, fill, _) => SizedBox(
            height: 6,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarPainter(
                fill: fill,
                color: color,
                trackColor: cs.outlineVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  final double fill;
  final Color color, trackColor;
  const _BarPainter({
    required this.fill,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(99);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), r),
      Paint()..color = trackColor.withValues(alpha: 0.4),
    );
    if (fill <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * fill, size.height),
        r,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fill != fill || old.color != color || old.trackColor != trackColor;
}
