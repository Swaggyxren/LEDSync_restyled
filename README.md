# LEDSync

LEDSync is a small Android + Flutter project that syncs your phone’s LED effects with **notifications** (and battery events, depending on your setup/device support).

> ⚠️ **Disclaimer / Credits**
> This project was **mostly made with AI assistance**.  
> I made this mainly because I was bored and wanted to experiment.  
> Expect bugs, rough edges, and device-specific behavior.

---

## Features

- ✅ **Notification LED Sync**
  - Uses Android **Notification Listener** permission.
  - Triggers the LED effect you assign per app/package (saved in Flutter SharedPreferences).
- ✅ **LED Lab / Effects Menu**
  - Manual testing / preview of effects.
- ✅ **Root-based LED control**
  - Writes to device LED nodes (sysfs) via `su`.
- ✅ **Battery listener (optional)**
  - Can trigger effects for low/critical/full battery depending on your implementation.

---

## Requirements

- Android device with supported LED hardware + correct sysfs paths  
- **Root access** (Magisk / KernelSU / etc.)
- Notification access enabled:
  - Settings → Special access → **Notification access** → enable for LEDSync

---

## Setup / Install (APK)

### Option A: Build Release APK
```bash
flutter clean
flutter pub get
flutter build apk --release
