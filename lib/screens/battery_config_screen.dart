import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledsync/main.dart' show glassDecoration, kTextMuted, kTextDim;
import 'package:ledsync/core/battery_listener.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

class BatteryConfigScreen extends StatefulWidget {
  const BatteryConfigScreen({super.key});
  @override
  State<BatteryConfigScreen> createState() => _BatteryConfigScreenState();
}

class _BatteryConfigScreenState extends State<BatteryConfigScreen> {
  static const kLowName = "batt_low_effect_name";
  static const kCritName = "batt_critical_effect_name";
  static const kFullName = "batt_full_effect_name";
  static const kLowT = "batt_low_threshold";
  static const kCritT = "batt_critical_threshold";
  static const kFullT = "batt_full_threshold";

  late final Future<DeviceConfig?> _cfgFuture;
  static const _defaultLowEffect = 'Rise';
  static const _defaultCriticalEffect = 'Lightning';
  static const _defaultFullEffect = 'Pureness';

  String? _lowEffect, _critEffect, _fullEffect;
  int _lowT = 20, _critT = 10, _fullT = 100;
  bool _dirty = false;
  int _battLevel = 0;
  bool _battCharging = false;
  final _battery = Battery();

  @override
  void initState() {
    super.initState();
    _cfgFuture = RootLogic.getConfig();
    _loadPrefs();
    _loadBattery();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final cfg = await _cfgFuture;
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

  String? _resolveEffect(String? chosen, {required String fallback, required DeviceConfig? cfg}) {
    if (cfg == null) return chosen ?? fallback;
    if (chosen != null && cfg.ledEffects.containsKey(chosen)) return chosen;
    if (cfg.ledEffects.containsKey(fallback)) return fallback;
    return chosen;
  }

  Future<void> _loadBattery() async {
    try {
      final level   = await _battery.batteryLevel;
      final state   = await _battery.batteryState;
      if (!mounted) return;
      setState(() {
        _battLevel    = level;
        _battCharging = state == BatteryState.charging || state == BatteryState.full;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kLowName, _lowEffect ?? "");
    await sp.setString(kCritName, _critEffect ?? "");
    await sp.setString(kFullName, _fullEffect ?? "");
    await sp.setInt(kLowT, _lowT);
    await sp.setInt(kCritT, _critT);
    await sp.setInt(kFullT, _fullT);

    // Re-evaluate immediately so users don't need to wait for next poll/event.
    await BatteryListener.refreshNow();

    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Saved battery LED settings",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Color(0xFF1A2942),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [Color(0xFF1e293b), Color(0xFF0a0a1a)],
          ),
        ),
        child: Column(children: [
          // Header
          Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: topPad + 16, bottom: 8),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(Icons.arrow_back, color: Color(0xFF3B82F6), size: 20),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text("Battery LED",
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                ),
              ),
              const SizedBox(width: 40),
            ]),
          ),

          Expanded(
            child: FutureBuilder<DeviceConfig?>(
              future: _cfgFuture,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
                }
                final cfg = snap.data;
                if (cfg == null) {
                  return const Center(child: Text("Device not supported",
                      style: TextStyle(color: Color(0xFF8899AA))));
                }
                final effects = cfg.ledEffects.keys.toList()..sort();
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Battery ring
                    _batteryRing(),
                    const SizedBox(height: 28),

                    // Thresholds
                    _sectionHeader("Thresholds"),
                    const SizedBox(height: 12),
                    _threshCard(
                      icon: Icons.battery_2_bar, iconColor: const Color(0xFF3B82F6),
                      label: "Low Battery", sub: "$_lowT% Threshold",
                      min: 5, max: 50, value: _lowT,
                      onDec: _lowT > 5 ? () => setState(() { _lowT--; _dirty = true; }) : null,
                      onInc: _lowT < 50 ? () => setState(() { _lowT++; _dirty = true; }) : null,
                    ),
                    const SizedBox(height: 10),
                    _threshCard(
                      icon: Icons.battery_alert, iconColor: Colors.orange,
                      label: "Critical Battery", sub: "$_critT% Threshold",
                      min: 1, max: 30, value: _critT,
                      onDec: _critT > 1 ? () => setState(() { _critT--; _dirty = true; }) : null,
                      onInc: _critT < 30 ? () => setState(() { _critT++; _dirty = true; }) : null,
                    ),
                    const SizedBox(height: 10),
                    _threshCard(
                      icon: Icons.battery_full, iconColor: const Color(0xFF22C55E),
                      label: "Full Battery", sub: "$_fullT% Threshold",
                      min: 90, max: 100, value: _fullT,
                      onDec: _fullT > 90 ? () => setState(() { _fullT--; _dirty = true; }) : null,
                      onInc: _fullT < 100 ? () => setState(() { _fullT++; _dirty = true; }) : null,
                    ),

                    const SizedBox(height: 28),
                    _sectionHeader("Visual Effects"),
                    const SizedBox(height: 12),

                    _effectRow(
                      icon: Icons.trending_up_rounded,
                      label: "Low Battery Pattern (default: Rise)",
                      value: _lowEffect,
                      items: effects,
                      onChanged: (v) => setState(() { _lowEffect = v; _dirty = true; }),
                    ),
                    const SizedBox(height: 10),
                    _effectRow(
                      icon: Icons.flash_on_rounded,
                      label: "Critical Battery Pattern (default: Lightning)",
                      value: _critEffect,
                      items: effects,
                      onChanged: (v) => setState(() { _critEffect = v; _dirty = true; }),
                    ),
                    const SizedBox(height: 10),
                    _effectRow(
                      icon: Icons.battery_full,
                      label: "Full Charge Pattern (default: Pureness)",
                      value: _fullEffect,
                      items: effects,
                      onChanged: (v) => setState(() { _fullEffect = v; _dirty = true; }),
                    ),

                    const SizedBox(height: 14),
                    Text(
                      "Tip: choose a pattern per threshold. Defaults are Rise (Low), Lightning (Critical), and Pureness (Full).\nFull-charge indication stays active while charging and stops after you unplug power.",
                      style: TextStyle(color: kTextDim, fontSize: 12),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _dirty
          ? FloatingActionButton.extended(
              onPressed: _save,
              backgroundColor: const Color(0xFF3B82F6),
              icon: const Icon(Icons.save_rounded),
              label: Text("Save Configuration",
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            )
          : null,
    );
  }

  Widget _batteryRing() {
    const size = 128.0;
    const r = size / 2 - 8;
    final progress = _battLevel / 100.0;
    // Ring colour shifts green → orange → red with charge level
    final ringColor = _battCharging
        ? const Color(0xFF22C55E)
        : _battLevel > 40
            ? const Color(0xFF3B82F6)
            : _battLevel > 20
                ? Colors.orange
                : Colors.red;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: glassDecoration(radius: 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: size, height: size,
                child: Stack(alignment: Alignment.center, children: [
                  Transform.rotate(
                    angle: -1.5708,
                    child: CustomPaint(
                      size: const Size(size, size),
                      painter: _RingPainter(progress: progress, r: r, color: ringColor),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text("$_battLevel%",
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
                    Text(_battCharging ? "CHARGING" : "CURRENT",
                        style: TextStyle(
                            color: _battCharging ? const Color(0xFF22C55E) : kTextDim,
                            fontSize: 9, letterSpacing: 2)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(text,
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17)),
    ],
  );

  Widget _threshCard({
    required IconData icon, required Color iconColor,
    required String label, required String sub,
    required int min, required int max, required int value,
    required VoidCallback? onDec, required VoidCallback? onInc,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: glassDecoration(radius: 18),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(sub, style: TextStyle(color: kTextDim, fontSize: 12)),
              ]),
            ),
            Row(children: [
              _iconBtn(Icons.remove, onDec),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text("$value%",
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              _iconBtn(Icons.add, onInc),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: onTap != null ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon,
          color: onTap != null ? kTextMuted : kTextDim.withValues(alpha: 0.3), size: 18),
    ),
  );

  Widget _effectRow({
    required IconData icon, required String label,
    required String? value, required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: glassDecoration(radius: 18),
          child: Row(children: [
            Icon(icon, color: kTextDim, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            DropdownButton<String?>(
              value: value,
              hint: Text("None", style: TextStyle(color: kTextDim, fontSize: 12)),
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF1A2942),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              icon: Icon(Icons.keyboard_arrow_down, color: kTextDim, size: 18),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text("None", style: TextStyle(color: kTextDim))),
                ...items.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
              ],
              onChanged: onChanged,
            ),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress, r;
  final Color color;
  _RingPainter({required this.progress, required this.r, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(cx, cy), r, bg);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        0, progress * 2 * 3.14159, false, fg);
  }

  @override
  bool shouldRepaint(_) => true;
}