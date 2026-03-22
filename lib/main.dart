import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/core/battery_listener.dart';
import 'package:ledsync/core/notif_permission.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/screens/home_screen.dart';
import 'package:ledsync/screens/led_menu.dart';
import 'package:ledsync/screens/tweaks_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const LedApp());
}

// ─── Design Tokens ────────────────────────────────────────────────────────
// In widgets, prefer Theme.of(context).colorScheme over these const values.
const kSeedColor  = Color(0xFF9E5AED);
const kPrimary    = kSeedColor; // kept for legacy imports

// Kept at 0 — Scaffold.bottomNavigationBar now handles the clearance.
const kNavBarClearance = 0.0;

// Card image constants (home screen hero card)
const kCardImageAsset     = 'assets/Card.png';
const kCardImageOpacity   = 1.0;
const kCardImageAlignment = Alignment.centerRight;

// Terminal / console accent colours
const kConsoleBlue   = Color(0xFF93C5FD);
const kConsoleBorder = Color(0xFF3B82F6);
const kConsoleBg     = Color(0xFF090D18);

// ─── App ─────────────────────────────────────────────────────────────────
class LedApp extends StatelessWidget {
  const LedApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kSeedColor,
            brightness: Brightness.dark,
          ),
          textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme),
          cardTheme: const CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            indicatorShape: StadiumBorder(),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
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
      duration: const Duration(milliseconds: 300),
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
      _navIndex  = i;
    });
    _slideCtrl.forward(from: 0);
  }

  static const List<Widget> _pages = [
    HomeScreen(),
    LedMenu(),
    TweaksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: AnimatedBuilder(
        animation: _slideCurve,
        builder: (ctx, child) {
          if (!_slideCtrl.isAnimating) return child!;
          final w          = MediaQuery.of(ctx).size.width;
          final goingRight = _navIndex > _prevIndex;
          final dx         = w * 0.06 * (1.0 - _slideCurve.value) * (goingRight ? 1.0 : -1.0);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: IndexedStack(
          index: _navIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavTap,
        backgroundColor: cs.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.$2),
                  selectedIcon: Icon(t.$1),
                  label: t.$3,
                ))
            .toList(),
      ),
    );
  }
}
