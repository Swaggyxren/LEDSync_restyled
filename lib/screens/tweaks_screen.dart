import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/screens/battery_config_screen.dart';
import 'package:ledsync/screens/notification_config_screen.dart';

class TweaksScreen extends StatelessWidget {
  const TweaksScreen({super.key});

  void _slide(BuildContext ctx, Widget page) {
    Navigator.of(ctx).push(PageRouteBuilder(
      pageBuilder: (ctx, a1, a2) => page,
      transitionsBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutQuint))
            .animate(anim),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tweaks',
              style: GoogleFonts.spaceGrotesk(
                color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 26)),
          const SizedBox(height: 24),

          // Section label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('LED CONFIGURATION',
                style: TextStyle(
                  color: cs.outline,
                  fontWeight: FontWeight.w600,
                  fontSize: 11, letterSpacing: 1.5)),
          ),

          _tile(
            context,
            icon: Icons.notifications_active_outlined,
            iconColor: cs.onSecondaryContainer,
            iconBg: cs.secondaryContainer,
            title: 'App Alerts',
            sub: 'Per-app notification LED patterns',
            onTap: () => _slide(context, const NotificationConfigScreen()),
          ),
          const SizedBox(height: 8),
          _tile(
            context,
            icon: Icons.battery_charging_full_outlined,
            iconColor: cs.onPrimaryContainer,
            iconBg: cs.primaryContainer,
            title: 'Battery Config',
            sub: 'Low / critical thresholds & effects',
            onTap: () => _slide(context, const BatteryConfigScreen()),
          ),
        ]),
      ),
    );
  }

  Widget _tile(
    BuildContext ctx, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(ctx).colorScheme;
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: GoogleFonts.spaceGrotesk(
                      color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 22),
          ]),
        ),
      ),
    );
  }
}
