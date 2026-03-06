import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ledsync/main.dart' show kPrimary, kTextDim;

class NotifPermission {
  static const _ch = MethodChannel('ledsync/notif_listener');

  static Future<bool> isEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('isEnabled') == true;
    } catch (_) { return false; }
  }

  static Future<void> openSettings() async {
    try { await _ch.invokeMethod('openSettings'); } catch (_) {}
  }

  // ── Waiting dialog ─────────────────────────────────────────────────────────
  static Future<void> _waitUntilEnabled(BuildContext context) async {
    if (!context.mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "WaitingPermission",
      barrierColor: Colors.black.withValues(alpha: 0.6),
      pageBuilder: (ctx, _, _) => _WaitingDialog(),
    );

    Timer? timer;
    timer = Timer.periodic(const Duration(milliseconds: 450), (_) async {
      final ok = await isEnabled();
      if (ok) {
        timer?.cancel();
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  // ── Permission dialog ──────────────────────────────────────────────────────
  static Future<void> ensureEnabled(BuildContext context) async {
    final ok = await isEnabled();
    if (ok || !context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "NotifPermission",
      barrierColor: Colors.black.withValues(alpha: 0.5),
      pageBuilder: (ctx, _, _) => _PermissionDialog(
        onOpenSettings: () async {
          Navigator.of(ctx, rootNavigator: true).pop();
          await openSettings();
          if (context.mounted) await _waitUntilEnabled(context);
        },
        onDismiss: () => Navigator.of(ctx, rootNavigator: true).pop(),
      ),
    );
  }
}

// ── Permission Required Dialog ────────────────────────────────────────────────
class _PermissionDialog extends StatelessWidget {
  final VoidCallback onOpenSettings, onDismiss;
  const _PermissionDialog({required this.onOpenSettings, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Material(
        color: Colors.black.withValues(alpha: 0.2),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Stack(children: [
                      // Top glow
                      Positioned(top: -60, left: -60,
                        child: Container(width: 150, height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kPrimary.withValues(alpha: 0.2),
                            boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.2), blurRadius: 60)],
                          ))),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 36, 28, 0),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          // Icon
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kPrimary.withValues(alpha: 0.2),
                              border: Border.all(color: kPrimary.withValues(alpha: 0.3), width: 2),
                            ),
                            child: Icon(Icons.notifications_active, color: kPrimary, size: 36),
                          ),
                          const SizedBox(height: 24),
                          Text("Permission required",
                              style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Text(
                            "To sync LEDs with notifications, enable Notification Access for this app.",
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14, height: 1.5),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: ElevatedButton(
                              onPressed: onOpenSettings,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                elevation: 0,
                              ),
                              child: Text("Open Settings",
                                  style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: OutlinedButton(
                              onPressed: onDismiss,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                              ),
                              child: Text("Not now",
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Waiting Dialog ────────────────────────────────────────────────────────────
class _WaitingDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Material(
        color: Colors.black.withValues(alpha: 0.2),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Ring progress
                      SizedBox(
                        width: 88, height: 88,
                        child: Stack(alignment: Alignment.center, children: [
                          const CircularProgressIndicator(
                            value: 0.3,
                            color: kPrimary,
                            backgroundColor: Color(0x1A9e5aed),
                            strokeWidth: 5,
                          ),
                          Icon(Icons.notifications_active, color: kPrimary, size: 30),
                        ]),
                      ),
                      const SizedBox(height: 22),
                      Text("Waiting for Notification Access...",
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      Text(
                        "Enable it in your system settings, then come back.",
                        style: TextStyle(color: kTextDim, fontSize: 13, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text("SYSTEM SYNCING",
                          style: TextStyle(
                              color: kTextDim, fontSize: 9, letterSpacing: 2,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
