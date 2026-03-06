import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ledsync/main.dart' show glassDecoration, kNavyEnd, kNavyStart, kNavBarClearance, kPrimary, kTextDim;
import 'package:ledsync/screens/battery_config_screen.dart';
import 'package:ledsync/screens/notification_config_screen.dart';

class TweaksScreen extends StatelessWidget {
  const TweaksScreen({super.key});

  void _slide(BuildContext ctx, Widget page) {
    Navigator.of(ctx).push(PageRouteBuilder(
      pageBuilder: (ctx, a1, a2) => page,
      transitionsBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutQuint)).animate(anim),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return SizedBox.expand(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kNavyStart, kNavyEnd],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPrimary.withValues(alpha: 0.1),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.1),
                    blurRadius: 80,
                    spreadRadius: 30,
                  ),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, topPad + 16, 20, kNavBarClearance + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'Tweaks',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 26,
                    ),
                  ),
                ),
                const Text(
                  'LED CONFIGURATION',
                  style: TextStyle(
                    color: kTextDim,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                _tile(
                  context,
                  icon: Icons.notifications_active_outlined,
                  iconColor: const Color(0xFF60A5FA),
                  iconBg: const Color(0xFF3B82F6),
                  title: 'App Alerts',
                  sub: 'Per-app notification LED patterns',
                  onTap: () => _slide(context, const NotificationConfigScreen()),
                ),
                const SizedBox(height: 10),
                _tile(
                  context,
                  icon: Icons.battery_charging_full_outlined,
                  iconColor: kPrimary,
                  iconBg: kPrimary,
                  title: 'Battery Config',
                  sub: 'Low / critical thresholds & effects',
                  onTap: () => _slide(context, const BatteryConfigScreen()),
                ),
              ],
            ),
          ),
          ],
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: glassDecoration(radius: 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg.withValues(alpha: 0.15),
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
                        title,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(color: kTextDim, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: kTextDim, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
