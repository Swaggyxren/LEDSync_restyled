import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ledsync/core/battery_listener.dart';
import 'package:ledsync/core/notif_permission.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/screens/home_screen.dart';
import 'package:ledsync/screens/led_menu.dart';
import 'package:ledsync/screens/tweaks_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const LedApp());
}

// ─── Design Tokens ────────────────────────────────────────────────────────
const kSeedColor = Color(0xFF9E5AED);
const kPrimary = kSeedColor;
const kNavBarClearance = 0.0;
const kCardImageAsset = 'assets/Card.png';
const kCardImageOpacity = 1.0;
const kCardImageAlignment = Alignment.centerRight;
const kConsoleBlue = Color(0xFF93C5FD);
const kConsoleBorder = Color(0xFF3B82F6);
const kConsoleBg = Color(0xFF090D18);

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
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'SpaceGrotesk'),
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

  // Fade controller — FadeTransition has no single-frame flash unlike
  // the previous Transform.translate approach which glitched on fast taps.
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const _tabs = [
    (Icons.home_rounded, Icons.home_outlined, 'Home'),
    (Icons.lightbulb_rounded, Icons.lightbulb_outline, 'LEDs'),
    (Icons.tune_rounded, Icons.tune, 'Tweaks'),
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

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.value = 1.0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotifPermission.ensureEnabled(context);
      BatteryListener.refreshNow();
    }
  }

  void _onNavTap(int i) {
    if (i == _navIndex) return;
    // Fade out → switch → fade in
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _navIndex = i);
      _fadeCtrl.forward();
    });
  }

  static const List<Widget> _pages = [HomeScreen(), LedMenu(), TweaksScreen()];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: IndexedStack(index: _navIndex, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavTap,
        backgroundColor: cs.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: _tabs
            .map(
              (t) => NavigationDestination(
                icon: Icon(t.$2),
                selectedIcon: Icon(t.$1),
                label: t.$3,
              ),
            )
            .toList(),
      ),
    );
  }
}
