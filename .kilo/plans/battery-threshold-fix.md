# Fix: Battery Threshold Patterns Not Triggering Reliably

## Problem
Battery config screen shows stale battery level (reads once in `initState`, never updates).
BatteryListener doesn't re-check when app returns to foreground — stream may not fire while backgrounded on some Android versions.

## Root Cause
Three gaps in the battery state lifecycle:
1. `BatteryConfigScreen._loadBattery()` — one-shot read, no stream
2. `MainShell.didChangeAppLifecycleState()` — only calls `NotifPermission.ensureEnabled`, never refreshes battery
3. `BatteryListener._checkNow()` — only runs on stream event + 20s poll, not on foreground resume

## Fixes

### Fix 1: BatteryConfigScreen — live battery updates

**File:** `lib/screens/battery_config_screen.dart`

- Add a `StreamSubscription<BatteryState>` field to listen to `_battery.onBatteryStateChanged`
- In `initState`, subscribe and update `_battLevel`/`_battCharging` on each event
- Add `dispose()` method to cancel the subscription

```dart
StreamSubscription<BatteryState>? _battSub;

@override
void initState() {
  super.initState();
  _cfgFuture = RootLogic.getConfig();
  _loadPrefs();
  _loadBattery();
  _battSub = _battery.onBatteryStateChanged.listen((_) => _loadBattery());
}

@override
void dispose() {
  _battSub?.cancel();
  super.dispose();
}
```

### Fix 2: MainShell — refresh battery on app resume

**File:** `lib/main.dart`

- In `didChangeAppLifecycleState(AppLifecycleState.resumed)`, add `BatteryListener.refreshNow()` after `NotifPermission.ensureEnabled`

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    NotifPermission.ensureEnabled(context);
    BatteryListener.refreshNow();
  }
}
```

### Fix 3: BatteryListener — refresh on demand from any caller

**File:** `lib/core/battery_listener.dart`

- No changes needed. `refreshNow()` → `_checkNow()` already exists and works.
- The fix in Fix 2 triggers it on resume. The 20s poll handles background gaps.
- The stream listener handles real-time changes when app is in foreground.

## Files Modified

| File | Change |
|------|--------|
| `lib/screens/battery_config_screen.dart` | Add battery stream subscription + dispose |
| `lib/main.dart` | Add `BatteryListener.refreshNow()` on app resume |
