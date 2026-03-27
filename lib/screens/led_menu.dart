import 'package:flutter/material.dart';
import 'package:ledsync/main.dart'
    show kConsoleBg, kConsoleBorder, kConsoleBlue;
import 'package:ledsync/core/led_action_log.dart';
import 'package:ledsync/core/system_log.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

class LedMenu extends StatefulWidget {
  const LedMenu({super.key});
  @override
  State<LedMenu> createState() => _LedMenuState();
}

class _LedMenuState extends State<LedMenu> {
  final ScrollController _logScroll = ScrollController();

  // ALL state that must survive remounts is static.
  static bool _initDone = false;
  static bool _isReady = false;
  static DeviceConfig? _config;

  String? _activeEffect;

  static const _effects = [
    (Icons.lightbulb_outline, 'Breathing'),
    (Icons.flash_on, 'Strobe'),
    (Icons.filter_vintage, 'Rainbow'),
    (Icons.favorite_outline, 'Pulse'),
    (Icons.pause_circle_outline, 'Static'),
    (Icons.waves, 'Wave'),
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
          _logScroll.animateTo(
            _logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  String _ts() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
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
      _sysLog(
        '[${_ts()}] Hardware initialized via sysfs',
        level: SystemLogLevel.success,
      );
      _sysLog(
        '[${_ts()}] LED Controller: Active',
        level: SystemLogLevel.success,
      );
      _sysLog(
        '[${_ts()}] System Ready. Awaiting effect selection.',
        level: SystemLogLevel.success,
      );
      if (mounted) setState(() => _isReady = true);
    } else {
      if (!mounted) return;
      _sysLog(
        '[${_ts()}] CRITICAL: No Root Access.',
        level: SystemLogLevel.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    final logs = LedActionLog.instance.entries;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────────────
          Container(
            color: cs.surface,
            padding: EdgeInsets.only(
              top: topPad + 4,
              bottom: 4,
              left: 8,
              right: 8,
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Text(
                  'LED Hardware Lab',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable content ───────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ledConsole(cs, logs),
                  const SizedBox(height: 24),
                  _sectionLabel(cs, 'EFFECT GRID'),
                  const SizedBox(height: 12),
                  _effectGrid(cs),
                ],
              ),
            ),
          ),

          // ── Emergency kill button ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.emergency_rounded, size: 20),
              label: const Text(
                'EMERGENCY KILL / RESTART',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: () async {
                _ledLog(
                  '[${_ts()}] Emergency Stop — killing LED service…',
                  level: LedActionLevel.warning,
                );
                _sysLog(
                  '[${_ts()}] Emergency Stop triggered by user.',
                  level: SystemLogLevel.warning,
                );
                setState(() {
                  _isReady = false;
                  _activeEffect = null;
                });
                await RootLogic.emergencyKillAndRevive();
                if (!mounted) return;
                _ledLog(
                  '[${_ts()}] Service restarted successfully.',
                  level: LedActionLevel.success,
                );
                _sysLog(
                  '[${_ts()}] Hardware service restarted. Re-initializing…',
                );
                _initLab(force: true);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── LED console terminal ──────────────────────────────────────────────
  Widget _ledConsole(ColorScheme cs, List<LedActionEntry> logs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel(cs, 'LED CONSOLE'),
            Text(
              'sysfs v2',
              style: TextStyle(
                color: cs.primary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 164,
          decoration: BoxDecoration(
            color: kConsoleBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kConsoleBorder.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              // Terminal title bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: kConsoleBorder.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _consoleDot(Colors.red.shade400),
                    const SizedBox(width: 5),
                    _consoleDot(Colors.amber.shade400),
                    const SizedBox(width: 5),
                    _consoleDot(Colors.green.shade400),
                    const SizedBox(width: 10),
                    Text(
                      'led-console',
                      style: TextStyle(
                        color: cs.outline,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // Log entries
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: logs.isEmpty
                      ? Center(
                          child: Text(
                            'No LED activity yet.\nPress an effect below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kConsoleBlue.withValues(alpha: 0.35),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _logScroll,
                          itemCount: logs.length + 1,
                          itemBuilder: (_, i) {
                            if (i < logs.length) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  logs[i].message,
                                  style: TextStyle(
                                    color: _actionColor(logs[i].level),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              );
                            }
                            return Row(
                              children: [
                                Text(
                                  '> ',
                                  style: TextStyle(
                                    color: kConsoleBorder,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const _BlinkingCursor(),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _actionColor(LedActionLevel l) {
    switch (l) {
      case LedActionLevel.success:
        return const Color(0xFF4ADE80);
      case LedActionLevel.warning:
        return const Color(0xFFFBBF24);
      case LedActionLevel.error:
        return const Color(0xFFF87171);
      case LedActionLevel.info:
        return kConsoleBlue;
    }
  }

  // ── Effect grid ───────────────────────────────────────────────────────
  Widget _effectGrid(ColorScheme cs) {
    if (!_isReady || _config == null) {
      // Show disabled placeholder chips while not ready
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _effects
            .map((e) => _chip(cs, e.$2, e.$1, false, null))
            .toList(),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _config!.ledEffects.entries.map((entry) {
        final active = _activeEffect == entry.key;
        final iconEntry = _effects.firstWhere(
          (e) => e.$2.toLowerCase() == entry.key.toLowerCase(),
          orElse: () => (Icons.lightbulb_outline, entry.key),
        );
        return _chip(cs, entry.key, iconEntry.$1, active, () {
          RootLogic.sendRawHex(entry.value);
          _ledLog(
            '[${_ts()}] Effect active: ${entry.key}',
            level: LedActionLevel.success,
          );
          setState(() => _activeEffect = entry.key);
        });
      }).toList(),
    );
  }

  Widget _chip(
    ColorScheme cs,
    String label,
    IconData icon,
    bool active,
    VoidCallback? onTap,
  ) {
    return FilterChip(
      selected: active,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
      label: Text(label),
      onSelected: onTap != null ? (_) => onTap() : null,
      selectedColor: cs.primaryContainer,
      backgroundColor: cs.surfaceContainerHigh,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
      side: BorderSide(
        color: active ? cs.primary : cs.outlineVariant,
        width: active ? 1.5 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) => Text(
    text,
    style: TextStyle(
      color: cs.outline,
      fontWeight: FontWeight.w600,
      fontSize: 11,
      letterSpacing: 1.4,
    ),
  );

  Widget _consoleDot(Color c) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
  );
}

// ─── Blinking terminal cursor ─────────────────────────────────────────────
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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, _) => Opacity(
      opacity: _ctrl.value > 0.5 ? 1 : 0,
      child: Container(
        width: 7,
        height: 13,
        color: kConsoleBorder.withValues(alpha: 0.7),
      ),
    ),
  );
}
