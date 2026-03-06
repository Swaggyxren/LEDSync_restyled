import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:ledsync/main.dart' show kPrimary, kGlassBg, kNavyStart, kNavBarClearance;
import 'package:ledsync/core/led_action_log.dart';
import 'package:ledsync/core/system_log.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

const _kConsoleBlue   = Color(0xFF93C5FD);
const _kConsoleBorder = Color(0xFF3B82F6);
const _kConsoleBg     = Color(0xFF0F1D2F);

class LedMenu extends StatefulWidget {
  const LedMenu({super.key});
  @override
  State<LedMenu> createState() => _LedMenuState();
}

class _LedMenuState extends State<LedMenu> {
  final ScrollController _logScroll = ScrollController();
  // ALL state that must survive remounts is static.
  // _initDone prevents re-running init; isReady + config hold the result.
  static bool          _initDone = false;
  static bool          _isReady  = false;
  static DeviceConfig? _config;

  String? _activeEffect;

  static const _effects = [
    (Icons.lightbulb_outline,    'Breathing'),
    (Icons.flash_on,             'Strobe'),
    (Icons.filter_vintage,       'Rainbow'),
    (Icons.favorite_outline,     'Pulse'),
    (Icons.pause_circle_outline, 'Static'),
    (Icons.waves,                'Wave'),
  ];

  @override
  void initState() {
    super.initState();
    _initLab();
    LedActionLog.instance.version.addListener(_onLedLog);
  }

  @override
  void dispose() {
    LedActionLog.instance.version.removeListener(_onLedLog);
    _logScroll.dispose();
    super.dispose();
  }

  void _onLedLog() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 60), () {
        if (_logScroll.hasClients) {
          _logScroll.animateTo(_logScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    });
  }

  String _ts() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}:${n.second.toString().padLeft(2,'0')}';
  }

  void _ledLog(String msg, {LedActionLevel level = LedActionLevel.info}) =>
      LedActionLog.instance.log(msg, level: level);

  void _sysLog(String msg, {SystemLogLevel level = SystemLogLevel.info}) =>
      SystemLog.instance.log(msg, level: level);

  Future<void> _initLab({bool force = false}) async {
    if (_initDone && !force) return;
    _initDone = true;
    _config = await RootLogic.getConfig();
    if (!mounted) return;
    _sysLog('[${_ts()}] Initializing core components...');
    if (await RootLogic.isRooted()) {
      if (!mounted) return;
      await RootLogic.initializeHardware();
      if (!mounted) return;
      _sysLog('[${_ts()}] Hardware bridge secured via USB-C',        level: SystemLogLevel.success);
      _sysLog('[${_ts()}] PWM Controller: Active (12-bit)',          level: SystemLogLevel.success);
      _sysLog('[${_ts()}] System Ready. Awaiting effect selection.', level: SystemLogLevel.success);
      if (mounted) setState(() => _isReady = true);
    } else {
      if (!mounted) return;
      _sysLog('[${_ts()}] CRITICAL: No Root Access.', level: SystemLogLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad      = MediaQuery.of(context).padding.top;
    const killH       = 56.0;
    const bottomClear = kNavBarClearance + killH + 24.0 + 16.0;
    final logs        = LedActionLog.instance.entries;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [kNavyStart, Color(0xFF1A2942)],
        ),
      ),
      child: Stack(children: [
        Positioned(top: -80, right: -80,
          child: Container(width: 240, height: 240,
            decoration: const BoxDecoration(shape: BoxShape.circle,
              color: Color(0x26915AED),
              boxShadow: [BoxShadow(color: Color(0x26915AED), blurRadius: 80, spreadRadius: 40)]))),

        Positioned.fill(child: Stack(children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, topPad + 56, 20, bottomClear),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ledConsole(logs),
              const SizedBox(height: 24),
              _sectionLabel('EFFECT GRID'),
              const SizedBox(height: 12),
              _effectGrid(),
            ]),
          ),
          Positioned(top: 0, left: 0, right: 0,
            height: topPad + 160,
            child: const IgnorePointer(child: _HeaderFade())),
          Positioned(top: 0, left: 0, right: 0,
            child: Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: topPad + 8, bottom: 10),
              child: Center(child: Text('LED Hardware Lab',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.bold, fontSize: 17, fontFamily: 'SpaceGrotesk'))),
            )),
        ])),

        Positioned(
          left: 20, right: 20, bottom: kNavBarClearance,
          child: GestureDetector(
            onTap: () async {
              _ledLog('[${_ts()}] Emergency Stop — killing LED service…', level: LedActionLevel.warning);
              _sysLog('[${_ts()}] Emergency Stop triggered by user.', level: SystemLogLevel.warning);
              setState(() { _isReady = false; _activeEffect = null; });
              await RootLogic.emergencyKillAndRevive();
              if (!mounted) return;
              _ledLog('[${_ts()}] Service restarted successfully.', level: LedActionLevel.success);
              _sysLog('[${_ts()}] Hardware service restarted. Re-initializing…');
              _initLab(force: true);
            },
            child: Container(
              height: killH,
              decoration: BoxDecoration(
                color: Colors.red[700],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.35), blurRadius: 20)],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.emergency, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('EMERGENCY KILL / RESTART',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                        fontSize: 15, fontFamily: 'SpaceGrotesk')),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _ledConsole(List<LedActionEntry> logs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sectionLabel('LED CONSOLE'),
        Text('BAUD: 115200',
            style: TextStyle(color: kPrimary.withValues(alpha: 0.8),
                fontSize: 10, fontFamily: 'monospace')),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 160,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kConsoleBg.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kConsoleBorder.withValues(alpha: 0.12)),
            ),
            child: logs.isEmpty
                ? Center(child: Text('No LED activity yet.\nPress an effect below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kConsoleBlue.withValues(alpha: 0.4),
                        fontSize: 11, fontFamily: 'monospace')))
                : ListView.builder(
                    controller: _logScroll,
                    itemCount: logs.length + 1,
                    itemBuilder: (_, i) {
                      if (i < logs.length) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(logs[i].message,
                              style: TextStyle(color: _actionColor(logs[i].level),
                                  fontSize: 11, fontFamily: 'monospace')),
                        );
                      }
                      return Row(children: [
                        Text('> ', style: TextStyle(color: _kConsoleBorder,
                            fontSize: 11, fontFamily: 'monospace')),
                        const _BlinkingCursor(),
                      ]);
                    },
                  ),
          ),
        ),
      ),
    ]);
  }

  Color _actionColor(LedActionLevel l) {
    switch (l) {
      case LedActionLevel.success: return const Color(0xFF22C55E);
      case LedActionLevel.warning: return const Color(0xFFF59E0B);
      case LedActionLevel.error:   return const Color(0xFFEF4444);
      case LedActionLevel.info:    return _kConsoleBlue;
    }
  }

  Widget _effectGrid() {
    if (!_isReady || _config == null) {
      return Wrap(spacing: 10, runSpacing: 10,
          children: _effects.map((e) => _chip(e.$2, e.$1, false, null)).toList());
    }
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: _config!.ledEffects.entries.map((entry) {
        final active = _activeEffect == entry.key;
        final iconEntry = _effects.firstWhere(
          (e) => e.$2.toLowerCase() == entry.key.toLowerCase(),
          orElse: () => (Icons.lightbulb_outline, entry.key),
        );
        return _chip(entry.key, iconEntry.$1, active, () {
          RootLogic.sendRawHex(entry.value);
          _ledLog('[${_ts()}] Effect active: ${entry.key}', level: LedActionLevel.success);
          setState(() => _activeEffect = entry.key);
        });
      }).toList(),
    );
  }

  Widget _chip(String label, IconData icon, bool active, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? kPrimary : kGlassBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active
              ? kPrimary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08)),
          boxShadow: active
              ? [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: 12)]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.9),
              fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'SpaceGrotesk')),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.55),
          fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 1.4));
}

class _HeaderFade extends StatelessWidget {
  const _HeaderFade();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [kNavyStart, Color(0xF50A1628), Color(0xD10A1628), Color(0x990A1628),
          Color(0x610A1628), Color(0x2E0A1628), Color(0x0F0A1628), Color(0x000A1628)],
        stops: [0.0, 0.12, 0.28, 0.50, 0.68, 0.82, 0.92, 1.0],
      ),
    ),
  );
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (ctx2, ch2) => Opacity(
      opacity: _ctrl.value > 0.5 ? 1 : 0,
      child: Container(width: 7, height: 14, color: _kConsoleBorder.withValues(alpha: 0.6)),
    ),
  );
}