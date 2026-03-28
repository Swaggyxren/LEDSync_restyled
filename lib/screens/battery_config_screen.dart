import 'dart:async';

import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledsync/core/battery_listener.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';
import 'package:ledsync/widgets/material3_loading.dart';

class BatteryConfigScreen extends StatefulWidget {
  const BatteryConfigScreen({super.key});
  @override
  State<BatteryConfigScreen> createState() => _BatteryConfigScreenState();
}

class _BatteryConfigScreenState extends State<BatteryConfigScreen> {
  static const kLowName = 'batt_low_effect_name';
  static const kCritName = 'batt_critical_effect_name';
  static const kFullName = 'batt_full_effect_name';
  static const kLowT = 'batt_low_threshold';
  static const kCritT = 'batt_critical_threshold';
  static const kFullT = 'batt_full_threshold';

  late final Future<DeviceConfig> _cfgFuture;
  static const _defaultLowEffect = 'Rise';
  static const _defaultCriticalEffect = 'Lightning';
  static const _defaultFullEffect = 'Pureness';

  String? _lowEffect, _critEffect, _fullEffect;
  int _lowT = 20, _critT = 10, _fullT = 100;
  bool _dirty = false;
  int _battLevel = 0;
  bool _battCharging = false;
  final _battery = Battery();
  StreamSubscription<BatteryState>? _battSub;

  @override
  void initState() {
    super.initState();
    _cfgFuture = RootLogic.getConfig();
    _loadPrefs();
    _loadBattery();
    _battSub = _battery.onBatteryStateChanged.listen((_) => _loadBattery());
  }

  @override
  void dispose() {
    _battSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final cfg = await _cfgFuture;
    if (!mounted) return;
    setState(() {
      _lowEffect = _resolveEffect(
        _nullIfEmpty(sp.getString(kLowName)),
        fallback: _defaultLowEffect,
        cfg: cfg,
      );
      _critEffect = _resolveEffect(
        _nullIfEmpty(sp.getString(kCritName)),
        fallback: _defaultCriticalEffect,
        cfg: cfg,
      );
      _fullEffect = _resolveEffect(
        _nullIfEmpty(sp.getString(kFullName)),
        fallback: _defaultFullEffect,
        cfg: cfg,
      );
      _lowT = (sp.getInt(kLowT) ?? 20).clamp(5, 50);
      _critT = (sp.getInt(kCritT) ?? 10).clamp(1, 30);
      _fullT = (sp.getInt(kFullT) ?? 100).clamp(90, 100);
      if (_critT >= _lowT) _critT = (_lowT - 5).clamp(1, _lowT - 1);
      _dirty = false;
    });
  }

  String? _nullIfEmpty(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  String? _resolveEffect(
    String? chosen, {
    required String fallback,
    required DeviceConfig? cfg,
  }) {
    if (cfg == null) return chosen ?? fallback;
    if (chosen != null && cfg.ledEffects.containsKey(chosen)) return chosen;
    if (cfg.ledEffects.containsKey(fallback)) return fallback;
    return chosen;
  }

  Future<void> _loadBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (!mounted) return;
      setState(() {
        _battLevel = level;
        _battCharging =
            state == BatteryState.charging || state == BatteryState.full;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kLowName, _lowEffect ?? '');
    await sp.setString(kCritName, _critEffect ?? '');
    await sp.setString(kFullName, _fullEffect ?? '');
    await sp.setInt(kLowT, _lowT);
    await sp.setInt(kCritT, _critT);
    await sp.setInt(kFullT, _fullT);
    await BatteryListener.refreshNow();
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Battery LED settings saved',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      ),
    );
  }

  // ── Colour helpers ────────────────────────────────────────────────────
  Color _ringColor(ColorScheme cs) {
    if (_battCharging) return cs.tertiary;
    if (_battLevel > 40) return cs.primary;
    if (_battLevel > 20) return Colors.orange;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            color: cs.surface,
            padding: EdgeInsets.only(
              left: 4,
              right: 16,
              top: topPad + 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Battery LED',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: FutureBuilder<DeviceConfig>(
              future: _cfgFuture,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const M3LoadingScreen(
                    message: 'Loading device config…',
                  );
                }
                final cfg = snap.data;
                if (cfg == null) {
                  return Center(
                    child: Text(
                      'Device not supported',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                final effects = cfg.ledEffects.keys.toList()..sort();

                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Battery ring ─────────────────────────────────────────
                      Center(child: _batteryRingCard(cs)),
                      const SizedBox(height: 28),

                      // ── Thresholds ───────────────────────────────────────────
                      _sectionHeader(context, 'Thresholds'),
                      const SizedBox(height: 10),

                      _threshCard(
                        cs: cs,
                        icon: Icons.battery_2_bar_rounded,
                        iconColor: cs.onPrimaryContainer,
                        iconBg: cs.primaryContainer,
                        label: 'Low Battery',
                        sub: '$_lowT% Threshold',
                        value: _lowT,
                        onDec: _lowT > 5
                            ? () => setState(() {
                                _lowT--;
                                _dirty = true;
                              })
                            : null,
                        onInc: _lowT < 50
                            ? () => setState(() {
                                _lowT++;
                                _dirty = true;
                              })
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _threshCard(
                        cs: cs,
                        icon: Icons.battery_alert_rounded,
                        iconColor: cs.onErrorContainer,
                        iconBg: cs.errorContainer,
                        label: 'Critical Battery',
                        sub: '$_critT% Threshold',
                        value: _critT,
                        onDec: _critT > 1
                            ? () => setState(() {
                                _critT--;
                                _dirty = true;
                              })
                            : null,
                        onInc: _critT < 30
                            ? () => setState(() {
                                _critT++;
                                _dirty = true;
                              })
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _threshCard(
                        cs: cs,
                        icon: Icons.battery_full_rounded,
                        iconColor: cs.onTertiaryContainer,
                        iconBg: cs.tertiaryContainer,
                        label: 'Full Battery',
                        sub: '$_fullT% Threshold',
                        value: _fullT,
                        onDec: _fullT > 90
                            ? () => setState(() {
                                _fullT--;
                                _dirty = true;
                              })
                            : null,
                        onInc: _fullT < 100
                            ? () => setState(() {
                                _fullT++;
                                _dirty = true;
                              })
                            : null,
                      ),

                      const SizedBox(height: 28),
                      _sectionHeader(context, 'Visual Effects'),
                      const SizedBox(height: 10),

                      _effectRow(
                        cs: cs,
                        icon: Icons.trending_up_rounded,
                        label: 'Low Battery Pattern',
                        hint: 'default: Rise',
                        value: _lowEffect,
                        items: effects,
                        onChanged: (v) => setState(() {
                          _lowEffect = v;
                          _dirty = true;
                        }),
                      ),
                      const SizedBox(height: 8),
                      _effectRow(
                        cs: cs,
                        icon: Icons.flash_on_rounded,
                        label: 'Critical Battery Pattern',
                        hint: 'default: Lightning',
                        value: _critEffect,
                        items: effects,
                        onChanged: (v) => setState(() {
                          _critEffect = v;
                          _dirty = true;
                        }),
                      ),
                      const SizedBox(height: 8),
                      _effectRow(
                        cs: cs,
                        icon: Icons.battery_full_rounded,
                        label: 'Full Charge Pattern',
                        hint: 'default: Pureness',
                        value: _fullEffect,
                        items: effects,
                        onChanged: (v) => setState(() {
                          _fullEffect = v;
                          _dirty = true;
                        }),
                      ),

                      const SizedBox(height: 16),
                      Card(
                        color: cs.surfaceContainerHigh,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: cs.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Choose a pattern per threshold. Defaults are Rise (Low), '
                                  'Lightning (Critical), and Pureness (Full). '
                                  'Full-charge indication stays active while charging.',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // ── Save FAB ──────────────────────────────────────────────────────
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _dirty
          ? FloatingActionButton.extended(
              onPressed: _save,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              icon: const Icon(Icons.save_rounded),
              label: Text(
                'Save Configuration',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontWeight: FontWeight.bold,
                ),
              ),
              shape: const StadiumBorder(),
            )
          : null,
    );
  }

  // ── Battery ring ──────────────────────────────────────────────────────
  Widget _batteryRingCard(ColorScheme cs) {
    const size = 128.0;
    const r = size / 2 - 10.0;
    final ringColor = _ringColor(cs);

    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: -1.5708,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _RingPainter(
                    progress: _battLevel / 100.0,
                    r: r,
                    color: ringColor,
                    trackColor: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_battLevel%',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                  Text(
                    _battCharging ? 'CHARGING' : 'CURRENT',
                    style: TextStyle(
                      color: _battCharging ? cs.tertiary : cs.outline,
                      fontSize: 9,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _threshCard({
    required ColorScheme cs,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String sub,
    required int value,
    required VoidCallback? onDec,
    required VoidCallback? onInc,
  }) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Stepper control
            Row(
              children: [
                _stepperBtn(cs, Icons.remove, onDec),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '$value%',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                _stepperBtn(cs, Icons.add, onInc),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperBtn(ColorScheme cs, IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: onTap != null
                ? cs.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: onTap != null
                ? cs.onSurface
                : cs.outline.withValues(alpha: 0.4),
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _effectRow({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(hint, style: TextStyle(color: cs.outline, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String?>(
              value: value,
              hint: Text(
                'None',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
              underline: const SizedBox(),
              dropdownColor: cs.surfaceContainerHigh,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: cs.outline,
                size: 18,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None', style: TextStyle(color: cs.outline)),
                ),
                ...items.map(
                  (e) => DropdownMenuItem<String?>(value: e, child: Text(e)),
                ),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ring painter ─────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress, r;
  final Color color, trackColor;
  _RingPainter({
    required this.progress,
    required this.r,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final bg = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(cx, cy), r, bg);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        0,
        progress * 2 * 3.14159,
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
