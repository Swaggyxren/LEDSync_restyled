import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledsync/main.dart' show kPrimary;
import 'package:ledsync/core/mapping_utils.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

// ─── CachedAppInfo (data model — unchanged) ───────────────────────────────
class CachedAppInfo {
  final String name, packageName;
  final String? iconBase64;
  CachedAppInfo({required this.name, required this.packageName, this.iconBase64});

  Map<String, dynamic> toJson() =>
      {'name': name, 'packageName': packageName, 'iconBase64': iconBase64};

  factory CachedAppInfo.fromJson(Map<String, dynamic> j) =>
      CachedAppInfo(name: j['name'], packageName: j['packageName'], iconBase64: j['iconBase64']);

  factory CachedAppInfo.fromAppInfo(AppInfo a) => CachedAppInfo(
        name: a.name,
        packageName: a.packageName,
        iconBase64: (a.icon != null && a.icon!.isNotEmpty) ? base64Encode(a.icon!) : null,
      );

  Uint8List? get iconBytes => iconBase64 != null ? base64Decode(iconBase64!) : null;
}

// ─── Screen ──────────────────────────────────────────────────────────────
class NotificationConfigScreen extends StatefulWidget {
  const NotificationConfigScreen({super.key});
  @override
  State<NotificationConfigScreen> createState() => _NotificationConfigScreenState();
}

class _NotificationConfigScreenState extends State<NotificationConfigScreen> {
  static const _kNameMapKey    = 'notif_name_map';
  static const _kHexMapKey     = 'notif_hex_map';
  static const _kShowSystemKey = 'notif_show_system_apps';
  static const _kCachedKey     = 'cached_apps_list';
  static const _kCachedSysKey  = 'cached_apps_list_system';
  static const _kTsKey         = 'cached_apps_timestamp';
  static const _kTsSysKey      = 'cached_apps_timestamp_system';
  // Keys read by the native NotificationLedService for looping-pattern teardown
  static const _kLoopingPkgsKey = 'notif_looping_pkgs';
  static const _kTurnOffHexKey  = 'notif_turnoff_hex';

  late final Future<DeviceConfig?> _cfgFuture;
  bool _showSystem = false, _reloading = false;
  List<CachedAppInfo> _apps  = [];
  Map<String, String> _saved = {}, _working = {};
  bool   _dirty  = false;
  String _search = '';
  final  _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cfgFuture = RootLogic.getConfig();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    _showSystem = sp.getBool(_kShowSystemKey) ?? false;
    final raw = sp.getString(_kNameMapKey);
    Map<String, String> parsed = {};
    if (raw != null && raw.isNotEmpty) {
      try { parsed = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v.toString())); }
      catch (_) {}
    }
    final cached = await _loadCache(_showSystem);
    if (!mounted) return;
    setState(() { _saved = parsed; _working = Map.of(parsed); _apps = cached; _dirty = false; });
    if (_apps.isEmpty || await _stale(_showSystem)) _reload(silent: true);
  }

  Future<List<CachedAppInfo>> _loadCache(bool sys) async {
    final sp = await SharedPreferences.getInstance();
    final j  = sp.getString(sys ? _kCachedSysKey : _kCachedKey);
    if (j == null || j.isEmpty) return [];
    try { return (jsonDecode(j) as List).map((e) => CachedAppInfo.fromJson(e)).toList(); }
    catch (_) { return []; }
  }

  Future<void> _saveCache(List<CachedAppInfo> apps, bool sys) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      sys ? _kCachedSysKey : _kCachedKey,
      jsonEncode(apps.map((e) => e.toJson()).toList()),
    );
    await sp.setInt(
      sys ? _kTsSysKey : _kTsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> _stale(bool sys) async {
    final sp = await SharedPreferences.getInstance();
    final ts = sp.getInt(sys ? _kTsSysKey : _kTsKey);
    if (ts == null) return true;
    return DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts))
        .inDays > 7;
  }

  Future<void> _reload({bool silent = false}) async {
    if (_reloading) return;
    if (!silent) setState(() => _reloading = true);
    try {
      final raw  = await InstalledApps.getInstalledApps(
          excludeSystemApps: !_showSystem, excludeNonLaunchableApps: false, withIcon: true);
      final apps = raw.map((e) => CachedAppInfo.fromAppInfo(e)).toList();
      await _saveCache(apps, _showSystem);
      if (!mounted) return;
      setState(() { _apps = apps; _reloading = false; });
      if (!silent) _showSnack('Loaded ${apps.length} apps');
    } catch (e) {
      if (!mounted) return;
      setState(() => _reloading = false);
      if (!silent) _showSnack('Failed: $e', isError: true);
    }
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) { if (b[e.key] != e.value) return false; }
    return true;
  }

  Future<void> _toggleSystem(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kShowSystemKey, v);
    setState(() => _showSystem = v);
    final cached = await _loadCache(v);
    if (!mounted) return;
    setState(() => _apps = cached);
    if (_apps.isEmpty || await _stale(v)) _reload(silent: true);
  }

  Future<void> _save(DeviceConfig cfg) async {
    final sp  = await SharedPreferences.getInstance();
    await sp.setString(_kNameMapKey, jsonEncode(_working));

    // Build hex map (packageName → hexCommand) for the native service
    final hex = <String, String>{};
    for (final e in _working.entries) {
      final h = cfg.ledEffects[e.value];
      if (h != null && h.trim().isNotEmpty) hex[e.key] = h;
    }
    await sp.setString(_kHexMapKey, jsonEncode(hex));

    // Build the set of packages whose assigned pattern loops infinitely.
    // The native NotificationLedService reads this on onNotificationRemoved
    // to know it must write the turn-off hex when the notification is cleared.
    final loopingPkgs = <String>{};
    for (final e in _working.entries) {
      if (cfg.loopingPatterns.contains(e.value)) {
        loopingPkgs.add(e.key);
      }
    }
    await sp.setStringList(_kLoopingPkgsKey, loopingPkgs.toList());

    // Store the device's turn-off hex so the native service doesn't need
    // to hard-code it.
    await sp.setString(_kTurnOffHexKey, cfg.turnOffHex);

    if (!mounted) return;
    setState(() { _saved = Map.of(_working); _dirty = false; });
    _showSnack('Saved app LED patterns');
  }

  void _showSnack(String text, {bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: isError ? cs.errorContainer : cs.inverseSurface,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(children: [
        // ── Header ────────────────────────────────────────────────────────
        Container(
          color: cs.surface,
          padding: EdgeInsets.only(
              left: 4, right: 8, top: topPad + 4, bottom: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text('App LED Sync',
                    style: GoogleFonts.spaceGrotesk(
                      color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 20)),
              ),
              // Refresh
              _reloading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.sync_rounded, color: cs.primary),
                      onPressed: _reload,
                      tooltip: 'Reload apps',
                    ),
              IconButton(
                icon: Icon(Icons.more_vert, color: cs.onSurface),
                onPressed: _openSearch,
              ),
            ]),
            // ── Search bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SearchBar(
                controller: _searchCtrl,
                hintText: 'Search installed apps…',
                leading: Icon(Icons.search, color: cs.onSurfaceVariant),
                onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                elevation: const WidgetStatePropertyAll(0),
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 16, vertical: 0)),
              ),
            ),
            // ── System apps toggle ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Card(
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.settings_suggest_outlined,
                          color: cs.onPrimaryContainer, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('System App Sync',
                            style: GoogleFonts.spaceGrotesk(
                              color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('Include system apps in LED effects',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                      ]),
                    ),
                    Switch(
                      value: _showSystem,
                      onChanged: _toggleSystem,
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),

        // ── App list ─────────────────────────────────────────────────────
        Expanded(
          child: FutureBuilder<DeviceConfig?>(
            future: _cfgFuture,
            builder: (_, cfgSnap) {
              if (cfgSnap.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: cs.primary));
              }
              final cfg = cfgSnap.data;
              if (cfg == null) {
                return Center(
                  child: Text('Device not supported',
                      style: TextStyle(color: cs.onSurfaceVariant)));
              }
              final effects = cfg.ledEffects;

              if (_apps.isEmpty && !_reloading) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircularProgressIndicator(color: cs.primary),
                  const SizedBox(height: 16),
                  Text('Loading apps…', style: TextStyle(color: cs.onSurfaceVariant)),
                ]));
              }

              var apps = List<CachedAppInfo>.from(_apps);
              if (_search.isNotEmpty) {
                apps.removeWhere((a) =>
                    !a.name.toLowerCase().contains(_search) &&
                    !a.packageName.toLowerCase().contains(_search));
              }
              apps.sort((a, b) {
                final aHas = _working.containsKey(a.packageName);
                final bHas = _working.containsKey(b.packageName);
                if (aHas != bHas) return aHas ? -1 : 1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('INSTALLED APPS',
                          style: TextStyle(
                            color: cs.outline, fontSize: 11,
                            fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      Text('${apps.length} found',
                          style: TextStyle(color: cs.outline, fontSize: 11)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: apps.length,
                    itemBuilder: (_, i) => _appCard(cs, apps[i], effects, cfg.loopingPatterns),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),

      // ── Save FAB ─────────────────────────────────────────────────────
      floatingActionButton: FutureBuilder<DeviceConfig?>(
        future: _cfgFuture,
        builder: (_, s) {
          final cfg = s.data;
          if (!_dirty || cfg == null) return const SizedBox.shrink();
          return FloatingActionButton(
            onPressed: () => _save(cfg),
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.save_rounded, size: 26),
          );
        },
      ),
    );
  }

  // ── App card ──────────────────────────────────────────────────────────
  Widget _appCard(ColorScheme cs, CachedAppInfo app, Map<String, String> effects,
      Set<String> loopingPatterns) {
    final sel        = _working[app.packageName];
    final hasPattern = sel != null && sel.trim().isNotEmpty;
    final isLooping  = hasPattern && loopingPatterns.contains(sel);

    return Card(
      color: hasPattern ? cs.primaryContainer.withValues(alpha: 0.25) : cs.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: hasPattern ? cs.primary.withValues(alpha: 0.5) : Colors.transparent,
          width: hasPattern ? 1.5 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // App icon
            _appIcon(cs, app.iconBytes),
            const SizedBox(width: 12),
            // App info
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.name,
                    style: GoogleFonts.spaceGrotesk(
                      color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(app.packageName,
                    style: TextStyle(
                      color: cs.outline, fontSize: 10, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            // Effect dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasPattern ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String?>(
                value: sel,
                hint: Text('None',
                    style: TextStyle(color: cs.outline, fontSize: 12)),
                underline: const SizedBox(),
                dropdownColor: cs.surfaceContainerHigh,
                isDense: true,
                style: TextStyle(
                  color: hasPattern ? cs.onPrimaryContainer : cs.onSurface,
                  fontSize: 12, fontWeight: FontWeight.w500),
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: hasPattern ? cs.onPrimaryContainer : cs.outline, size: 16),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None (Disabled)',
                        style: TextStyle(color: cs.outline))),
                  ...effects.keys.map((n) => DropdownMenuItem<String?>(
                      value: n,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(n),
                        if (loopingPatterns.contains(n)) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.loop_rounded, size: 12, color: cs.outline),
                        ],
                      ]))),
                ],
                onChanged: (v) => setState(() {
                  _working = setOptionalMapping(_working, key: app.packageName, value: v);
                  _dirty   = !_mapsEqual(_working, _saved);
                }),
              ),
            ),
          ]),
          // Looping-pattern notice
          if (isLooping) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.loop_rounded, size: 12, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Loops while notification is active — stops on dismiss',
                style: TextStyle(color: cs.primary, fontSize: 11),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _appIcon(ColorScheme cs, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.android, color: cs.outline, size: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, width: 48, height: 48,
          errorBuilder: (_, _, _) =>
              Icon(Icons.android, color: cs.outline, size: 26)),
    );
  }

  Future<void> _openSearch() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        _searchCtrl.text = _search;
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Search apps',
              style: GoogleFonts.spaceGrotesk(
                color: cs.onSurface, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Name or package…',
              hintStyle: TextStyle(color: cs.outline),
              prefixIcon: Icon(Icons.search, color: cs.outline),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: cs.outline)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: cs.primary)),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('Cancel', style: TextStyle(color: cs.outline))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text('Clear', style: TextStyle(color: cs.outline))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _searchCtrl.text.trim()),
              child: const Text('Apply')),
          ],
        );
      },
    );
    if (!mounted || result == null) return;
    setState(() => _search = result.toLowerCase());
    _searchCtrl.text = result;
  }
}
