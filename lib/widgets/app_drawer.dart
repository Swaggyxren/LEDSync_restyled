import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:ledsync/main.dart' show kPrimary, kTextDim, kTextMuted;
import 'package:ledsync/screens/battery_config_screen.dart';
import 'package:ledsync/screens/notification_config_screen.dart';

class AppDrawerPopup {
  static void show(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Close",
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, _) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: _DrawerContent(),
      ),
    );
  }
}

class _DrawerContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2942).withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                ),
                child: Stack(children: [
                  // Top glow
                  Positioned(top: -40, right: -40,
                    child: Container(width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimary.withValues(alpha: 0.15),
                        boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.15), blurRadius: 60)],
                      ))),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.tune, color: kPrimary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Text("LED Configuration",
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ]),
                      const SizedBox(height: 20),

                      _tile(context,
                        icon: Icons.notifications_active,
                        iconColor: const Color(0xFF60A5FA),
                        iconBg: const Color(0xFF3B82F6),
                        title: "App Alerts",
                        sub: "Per-app notification LED patterns",
                        screen: const NotificationConfigScreen(),
                      ),
                      const SizedBox(height: 10),
                      _tile(context,
                        icon: Icons.battery_charging_full,
                        iconColor: kPrimary,
                        iconBg: kPrimary,
                        title: "Battery Config",
                        sub: "Low / critical thresholds & effects",
                        screen: const BatteryConfigScreen(),
                      ),

                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Text("Close",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                  color: kTextMuted, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, {
    required IconData icon, required Color iconColor, required Color iconBg,
    required String title, required String sub, required Widget screen,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1D2F).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: iconBg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: kTextDim, fontSize: 12)),
              ])),
              Icon(Icons.chevron_right_rounded, color: kTextDim, size: 22),
            ]),
          ),
        ),
      ),
    );
  }
}
