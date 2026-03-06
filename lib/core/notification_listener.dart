/// Deprecated path.
///
/// Notification-to-LED triggering is handled by native Android service
/// (`NotificationLedService.kt`) using SharedPreferences key
/// `flutter.notif_hex_map`.
///
/// This class is kept only for compatibility and should not be used for new code.
@Deprecated('Use native NotificationLedService + flutter.notif_hex_map mapping')
class NotificationListener {
  @Deprecated('Unused in current architecture')
  static void onPackageReceived(String packageName) {
    // Intentionally no-op.
  }
}
