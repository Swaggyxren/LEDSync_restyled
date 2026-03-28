# Fix: Tooltip Appears While Permission Dialogs Still Showing

## Problem
`NotifPermission.ensureEnabled(context)` and `HomeScreen._maybeShowTooltip()` both fire on the same first frame via `addPostFrameCallback`. The tooltip's polling checks `isEnabled()` but has no way to know if a permission dialog is still on screen. If the user grants permission from the _WaitingDialog, `isEnabled()` becomes true before the dialog dismisses, causing the tooltip to appear on top of it.

## Root Cause
No shared state between NotifPermission (which shows dialogs) and HomeScreen (which shows tooltip). They run in parallel with no coordination.

## Fix

### 1. NotifPermission — expose dialog visibility state

**File:** `lib/core/notif_permission.dart`

Add a static bool `_dialogActive` that tracks whether any NotifPermission dialog is currently displayed:

- Set `_dialogActive = true` at the start of `_showDialog` and `_waitUntilEnabled`
- Set `_dialogActive = false` after the dialog future completes (in `ensureEnabled` and `_waitUntilEnabled`)
- Expose as `static bool get isDialogActive => _dialogActive`

### 2. HomeScreen — wait for dialog to dismiss before showing tooltip

**File:** `lib/screens/home_screen.dart`

In `_maybeShowTooltip`, after confirming `isEnabled()` is true, add an extra wait loop that also checks `!NotifPermission.isDialogActive`:

```
// Wait for permission to be granted AND no dialog to be on screen
while (mounted && !(await NotifPermission.isEnabled())) { ... poll ... }
while (mounted && NotifPermission.isDialogActive) { ... poll 500ms ... }
```

This ensures the tooltip only appears after:
1. Notification access is granted
2. All permission dialogs have fully dismissed

## Files Modified

| File | Change |
|------|--------|
| `lib/core/notif_permission.dart` | Add `_dialogActive` flag, expose `isDialogActive` getter |
| `lib/screens/home_screen.dart` | Add `isDialogActive` check in `_maybeShowTooltip` |
