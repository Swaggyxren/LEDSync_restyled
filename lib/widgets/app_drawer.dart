import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/screens/battery_config_screen.dart';
import 'package:ledsync/screens/notification_config_screen.dart';

class AppDrawerPopup {
  static void show(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, _) => const _DrawerContent(),
    );
  }
}

class _DrawerContent extends StatelessWidget {
  const _DrawerContent();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Card(
            color: cs.surfaceContainerHigh,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Title row
                Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune_rounded, color: cs.onPrimaryContainer, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text('LED Configuration',
                      style: GoogleFonts.spaceGrotesk(
                        color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 18)),
                ]),
                const SizedBox(height: 20),

                // App Alerts tile
                _tile(
                  context,
                  icon: Icons.notifications_active_rounded,
                  iconColor: cs.onSecondaryContainer,
                  iconBg: cs.secondaryContainer,
                  title: 'App Alerts',
                  sub: 'Per-app notification LED patterns',
                  screen: const NotificationConfigScreen(),
                ),
                const SizedBox(height: 8),

                // Battery Config tile
                _tile(
                  context,
                  icon: Icons.battery_charging_full_rounded,
                  iconColor: cs.onPrimaryContainer,
                  iconBg: cs.primaryContainer,
                  title: 'Battery Config',
                  sub: 'Low / critical thresholds & effects',
                  screen: const BatteryConfigScreen(),
                ),

                const SizedBox(height: 20),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Close',
                        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String sub,
    required Widget screen,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
        },
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
