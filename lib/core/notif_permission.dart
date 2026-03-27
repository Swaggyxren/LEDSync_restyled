import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NotifPermission {
  static const _ch = MethodChannel('ledsync/notif_listener');

  // Session flag — prevents re-showing dialogs if user dismissed in this session
  static bool _sessionDismissed = false;
  static Timer? _waitTimer;

  static Future<bool> isEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('isEnabled') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  static Future<bool> hasPostNotifications() async {
    try {
      return await _ch.invokeMethod<bool>('hasPostNotifications') == true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestPostNotifications() async {
    try {
      await _ch.invokeMethod('requestPostNotifications');
    } catch (_) {}
  }

  // ── Entry point ────────────────────────────────────────────────────────────
  static Future<void> ensureEnabled(BuildContext context) async {
    // Don't re-show dialogs if user already dismissed in this session
    if (_sessionDismissed) return;

    // Step 1: POST_NOTIFICATIONS (Android 13+)
    final hasPost = await hasPostNotifications();
    if (!hasPost && context.mounted) {
      await _showDialog(
        context,
        _PostNotifDialog(
          onAllow: () async {
            Navigator.of(context, rootNavigator: true).pop();
            await requestPostNotifications();
          },
          onDismiss: () {
            _sessionDismissed = true;
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
      );
    }

    if (_sessionDismissed) return;

    // Step 2: Notification listener access
    final ok = await isEnabled();
    if (ok || !context.mounted) return;

    await _showDialog(
      context,
      _PermissionDialog(
        onOpenSettings: () async {
          _sessionDismissed = false; // user is actively trying — allow re-check
          Navigator.of(context, rootNavigator: true).pop();
          await openSettings();
          if (context.mounted) await _waitUntilEnabled(context);
        },
        onDismiss: () {
          _sessionDismissed = true;
          Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );
  }

  static Future<void> _showDialog(BuildContext context, Widget child) =>
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: '',
        barrierColor: Colors.black.withValues(alpha: 0.55),
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (_, anim, _, w) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.95,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: w,
          ),
        ),
        pageBuilder: (_, _, _) => child,
      );

  static Future<void> _waitUntilEnabled(BuildContext context) async {
    if (!context.mounted) return;
    _waitTimer?.cancel();
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      pageBuilder: (_, _, _) => const _WaitingDialog(),
    );
    int elapsed = 0;
    _waitTimer = Timer.periodic(const Duration(milliseconds: 450), (t) async {
      elapsed += 450;
      if (await isEnabled()) {
        t.cancel();
        _waitTimer = null;
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      } else if (elapsed >= 60000) {
        t.cancel();
        _waitTimer = null;
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }
}

// ─── Shared card shell ────────────────────────────────────────────────────────
class _DialogCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _DialogCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primaryContainer,
                    ),
                    child: Icon(icon, color: cs.onPrimaryContainer, size: 34),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onPrimary,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: onSecondary,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(secondaryLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── POST_NOTIFICATIONS dialog ─────────────────────────────────────────────────
class _PostNotifDialog extends StatelessWidget {
  final VoidCallback onAllow, onDismiss;
  const _PostNotifDialog({required this.onAllow, required this.onDismiss});

  @override
  Widget build(BuildContext context) => _DialogCard(
    icon: Icons.notifications_rounded,
    title: 'Allow notifications',
    body:
        'LED Sync needs permission to show its background service notification on Android 13+.',
    primaryLabel: 'Allow',
    onPrimary: onAllow,
    secondaryLabel: 'Not now',
    onSecondary: onDismiss,
  );
}

// ─── Notification listener dialog ─────────────────────────────────────────────
class _PermissionDialog extends StatelessWidget {
  final VoidCallback onOpenSettings, onDismiss;
  const _PermissionDialog({
    required this.onOpenSettings,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => _DialogCard(
    icon: Icons.notifications_active_rounded,
    title: 'Notification access required',
    body:
        'To sync LEDs with notifications, enable Notification Access for LED Sync in system settings.',
    primaryLabel: 'Open Settings',
    onPrimary: onOpenSettings,
    secondaryLabel: 'Not now',
    onSecondary: onDismiss,
  );
}

// ─── Waiting dialog ────────────────────────────────────────────────────────────
class _WaitingDialog extends StatelessWidget {
  const _WaitingDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Card(
            color: cs.surfaceContainerHigh,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: cs.primary,
                          backgroundColor: cs.primaryContainer,
                          strokeWidth: 4,
                        ),
                        Icon(
                          Icons.notifications_active_rounded,
                          color: cs.primary,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Waiting for access…',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable Notification Access in settings, then come back.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
