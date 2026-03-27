# LEDSync: Codebase Cleanup + Material 3 Loading Plan

## Part 1: Dead Code Removal

### 1a. Delete `lib/core/notification_listener.dart`
- Entire file is `@Deprecated` with a no-op method. Nothing imports it.

### 1b. Delete `lib/core/led_automator.dart`
- Full priority/cooldown system (LedPriority, playEffect, emergencyKill) — nothing calls it.

### 1c. Delete `lib/widgets/app_drawer.dart`
- `AppDrawerPopup` is never referenced. `TweaksScreen` already provides the same two-tile navigation inline.

### 1d. Delete `lib/screens/logs_screen.dart`
- `LogsScreen` is never wired into navigation (`MainShell` tabs are Home/LEDs/Tweaks). Ghost screen.

### 1e. Remove imports referencing deleted files
- Verify no remaining imports reference the deleted files.

---

## Part 2: Unify Device Config List (Single Source of Truth)

**Problem:** `RootLogic.allConfigs` and `HomeScreen._supportedDevices` are two independent lists.

**Fix:**
- Remove `static final List<DeviceConfig> _supportedDevices` from `HomeScreen._HomeScreenState` (line 532-535).
- Replace `_supportedDevices` usage in `_showDevicePicker` (line 557) with `RootLogic.allConfigs`.

---

## Part 3: Extract CPU/RAM Parsing to Shared Utility

**Problem:** `_parseCpu()` and `_parseRam()` duplicated in `HomeScreen` and `PerformanceScreen`.

**Fix:**
- Create `lib/core/system_stats_parser.dart` with `SystemStatsParser` class:
  - `parseCpu(String statRaw, int prevIdle, int prevTotal)` → returns parsed cpu% + new baseline
  - `parseRam(String meminfoRaw)` → returns (usedMb, totalMb)
- Refactor both `HomeScreen` and `PerformanceScreen` to use it.
- Keep `_prevIdle`/`_prevTotal` state in each class (independent baselines).

---

## Part 4: Cap Log Lists (Memory Leak Fix)

**Problem:** `SystemLog._entries` and `LedActionLog._entries` grow unbounded.

**Fix:**
- Add `static const int _maxEntries = 500;` to both classes.
- In `log()`, after adding: `if (_entries.length > _maxEntries) _entries.removeAt(0);`

---

## Part 5: Fix Timer Leak in `_waitUntilEnabled`

**Problem:** `notif_permission.dart` line 98 — `Timer.periodic` never cancelled if dialog dismissed by other means.

**Fix:**
- Store timer in `static Timer? _waitTimer;` on `NotifPermission`.
- Cancel existing `_waitTimer` before creating new one.
- Cancel when `isEnabled()` is detected.
- Add 60-second hard timeout that auto-cancels and pops dialog.
- Store timer reference for cleanup.

---

## Part 6: Fix Tooltip Busy-Wait Loop

**Problem:** `home_screen.dart` line 419 — 60 × 500ms = 30 seconds of polling.

**Fix:**
- Replace `for` loop with `Timer.periodic` checking every 2 seconds.
- Hard 30-second timeout.
- Cancel in `dispose()` or when tooltip shown.

---

## Part 7: Fix `dynamic` Cast in `getPhoneInfo`

**Problem:** `root_logic.dart` line 63 — `as dynamic` duck-typing.

**Fix:**
- Change to `final androidInfo = results[0] as AndroidDeviceInfo;`
- `DeviceInfoPlugin().androidInfo` returns `Future<AndroidDeviceInfo>`, type is already imported.

---

## Part 8: Fix Nullable Return Type Mismatch

**Problem:** `getConfig()` says "never returns null" in comment but returns `Future<DeviceConfig?>`.

**Fix:**
- Change return type to `Future<DeviceConfig>` (non-nullable). The `orElse: () => LH8nConfig()` ensures it never returns null.
- Remove null checks at call sites: `ensureLedEnabled()`, `sendRawHex()`, `turnOffAll()`.

---

## Part 9: Remove `google_fonts` Dependency

**Problem:** Font bundled locally, `google_fonts` only used in `logs_screen.dart` (being deleted).

**Fix:**
- After deleting `logs_screen.dart`, remove `google_fonts: ^6.2.1` from `pubspec.yaml`.
- Run `flutter pub get`.

---

## Part 10: Add Debug Logging to `_runSu`

**Problem:** Root commands fail silently.

**Fix:**
- In `_runSu`, log on non-zero exit:
  ```dart
  if (result.exitCode != 0) {
    debugPrint('[RootLogic] su failed (exit ${result.exitCode}): $cmd');
  }
  ```
- Add `import 'package:flutter/foundation.dart';` to `root_logic.dart`.

---

## Part 11: Remove Redundant Search Dialog

**Problem:** `notification_config_screen.dart` has both inline `SearchBar` and dialog `_openSearch` for the same list.

**Fix:**
- Remove `_openSearch` method and the `more_vert` `IconButton` (lines 232-235).
- The inline `SearchBar` already handles search.

---

## Part 12: Remove Fake Hardware Strings

**Problem:** `led_menu.dart` — "BAUD: 115200", "USB-C", "12-bit PWM" are cosmetic fiction.

**Fix:**
- "BAUD: 115200" → remove or change to "sysfs v2"
- "Hardware bridge secured via USB-C" → "Hardware initialized via sysfs"
- "PWM Controller: Active (12-bit)" → "LED Controller: Active"

---

## Part 13: Android Codenames

**Problem:** `home_screen.dart` lines 94-102 hardcoded version→codename mapping.

**Note:** `androidInfo.version.codename` is empty for stable releases, so the manual map is pragmatic. Just add a comment that it needs periodic updates.

---

---

## Part 14: Material 3 Loading Indicators

Translate the blog post's M3 `LoadingIndicator` concepts (Contained/Uncontained, morphing shape, theming, accessibility) to Flutter equivalents.

### 14a. Create `lib/widgets/material3_loading.dart`

Three reusable widgets:

- **`M3LoadingContained`** — `CircularProgressIndicator` inside a 48dp `surfaceContainer` circle (M3 Contained spec: 48dp container, ~38dp indicator).
- **`M3LoadingUncontained`** — bare `CircularProgressIndicator` that blends with UI.
- **`M3LoadingScreen`** — contained spinner + label text, for `FutureBuilder` loading states.

All wrapped in `Semantics(label: ...)` for accessibility.

### 14b. Create `lib/widgets/shimmer_loading.dart`

- **`ShimmerBox`** — animated `LinearGradient` sweep for skeleton/shimmer loading on the HomeScreen device card while device info is being read.

### 14c. Replace Loading States

| File | Current | Replace With |
|------|---------|-------------|
| `battery_config_screen.dart:146` | bare `CircularProgressIndicator` | `M3LoadingScreen` |
| `notification_config_screen.dart:224` | inline `CircularProgressIndicator(strokeWidth: 2)` | `M3LoadingUncontained(size: 20)` |
| `notification_config_screen.dart:295` | bare `CircularProgressIndicator` | `M3LoadingScreen` |
| `notification_config_screen.dart:307` | `CircularProgressIndicator` + text | `M3LoadingScreen` |
| `notif_permission.dart:262` | Stack(CPI, Icon) | **Keep as-is** (already well-designed) |

### 14d. Add Shimmer to HomeScreen Device Card

While `_DeviceCache.ready == false`, replace static "Reading device…" text with shimmer placeholder blocks for model name, Android version, and kernel line.

---

## Execution Order

1. **Phase 1 — Dead code** (1a-1e): Delete 4 files. Zero risk.
2. **Phase 2 — Structural fixes** (2-13): Architecture, bugs, dependency cleanup.
3. **Phase 3 — M3 loading** (14a-14d): Loading widgets, shimmer, replace all loading states.

## Files Changed

| Action | File |
|--------|------|
| DELETE | `lib/core/notification_listener.dart` |
| DELETE | `lib/core/led_automator.dart` |
| DELETE | `lib/widgets/app_drawer.dart` |
| DELETE | `lib/screens/logs_screen.dart` |
| CREATE | `lib/widgets/material3_loading.dart` |
| CREATE | `lib/widgets/shimmer_loading.dart` |
| CREATE | `lib/core/system_stats_parser.dart` |
| EDIT | `lib/core/root_logic.dart` |
| EDIT | `lib/core/system_log.dart` |
| EDIT | `lib/core/led_action_log.dart` |
| EDIT | `lib/core/notif_permission.dart` |
| EDIT | `lib/screens/home_screen.dart` |
| EDIT | `lib/screens/performance_screen.dart` |
| EDIT | `lib/screens/battery_config_screen.dart` |
| EDIT | `lib/screens/notification_config_screen.dart` |
| EDIT | `lib/screens/led_menu.dart` |
| EDIT | `pubspec.yaml` |
