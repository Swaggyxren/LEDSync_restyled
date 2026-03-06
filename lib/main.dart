import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/core/battery_listener.dart';
import 'package:ledsync/core/notif_permission.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/screens/home_screen.dart';
import 'package:ledsync/screens/led_menu.dart';
import 'package:ledsync/screens/logs_screen.dart';
import 'package:ledsync/screens/tweaks_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A1628),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const LedApp());
}

// ─── Design Tokens ────────────────────────────────────────────────────────
// Glass UI: use ClipRRect → BackdropFilter(ImageFilter.blur) → Container(decoration: glassDecoration())
// so the background is blurred and the panel gets a consistent tint. Use ClampingScrollPhysics
// on scrollable screens so overscroll does not reveal unblurred gradient.
const kPrimary     = Color(0xFF9e5aed);
const kNavyStart   = Color(0xFF0A1628);
const kNavyEnd     = Color(0xFF1A2942);
const kTextMuted   = Color(0xFFB8C5D6);
const kTextDim     = Color(0xFF8899AA);
const kGlassBg     = Color(0x0DFFFFFF);
const kGlassBorder = Color(0x1AFFFFFF);

const kCardImageAsset     = 'assets/Card.png';
const kCardImageOpacity   = 1.0;
const kCardImageAlignment = Alignment.centerRight;

const kNavBarClearance = 100.0;

/// Semi-transparent fill + border for glass panels. Use with ClipRRect and BackdropFilter
/// so content behind the panel is blurred; this adds the tint on top.
BoxDecoration glassDecoration({double radius = 25, Color? borderColor}) =>
    BoxDecoration(
      color: kGlassBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? kGlassBorder, width: 1),
    );

// ─── App ─────────────────────────────────────────────────────────────────
class LedApp extends StatelessWidget {
  const LedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: kNavyStart,
      colorScheme: const ColorScheme.dark(primary: kPrimary, surface: kNavyEnd),
      textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme),
    ),
    home: const MainShell(),
  );
}

// ─── Main Shell ───────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _navIndex = 0;
  int _prevIndex = 0;

  late final AnimationController _slideCtrl;
  late final CurvedAnimation     _slideCurve;

  static const _tabs = [
    (Icons.home_rounded,      Icons.home_outlined,     'Home'),
    (Icons.lightbulb_rounded, Icons.lightbulb_outline, 'LEDs'),
    (Icons.terminal_rounded,  Icons.terminal,          'Logs'),
    (Icons.tune_rounded,      Icons.tune,              'Tweaks'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RootLogic.initializeHardware();
    BatteryListener.listen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotifPermission.ensureEnabled(context);
    });

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _slideCurve = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
    _slideCtrl.value = 1.0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) NotifPermission.ensureEnabled(context);
  }

  void _onNavTap(int i) {
    if (i == _navIndex) return;
    setState(() {
      _prevIndex = _navIndex;
      _navIndex = i;
    });
    _slideCtrl.forward(from: 0);
  }

  static const List<Widget> _pages = [
    HomeScreen(),
    LedMenu(),
    LogsScreen(),
    TweaksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _slideCurve,
            builder: (ctx, child) {
              if (!_slideCtrl.isAnimating) return child!;

              final w = MediaQuery.of(ctx).size.width;
              final goingRight = _navIndex > _prevIndex;
              final dx = w * 0.06 * (1.0 - _slideCurve.value) * (goingRight ? 1.0 : -1.0);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: IndexedStack(
              index: _navIndex,
              children: _pages,
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: glassDecoration(radius: 999),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(_tabs.length, (i) {
                      final sel = _navIndex == i;
                      return GestureDetector(
                        onTap: () => _onNavTap(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                sel ? _tabs[i].$1 : _tabs[i].$2,
                                color: sel ? kPrimary : kTextMuted,
                                size: 24,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _tabs[i].$3,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                                  color: sel ? kPrimary : kTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
