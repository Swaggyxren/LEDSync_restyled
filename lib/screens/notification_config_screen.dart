import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledsync/main.dart' show kPrimary, kTextDim;
import 'package:ledsync/core/mapping_utils.dart';
import 'package:ledsync/core/root_logic.dart';
import 'package:ledsync/models/devices/device_config.dart';

class CachedAppInfo {
  final String name, packageName;
  final String? iconBase64;
  CachedAppInfo({required this.name, required this.packageName, this.iconBase64});
  Map<String, dynamic> toJson() => {'name': name, 'packageName': packageName, 'iconBase64': iconBase64};
  factory CachedAppInfo.fromJson(Map<String, dynamic> j) =>
      CachedAppInfo(name: j['name'], packageName: j['packageName'], iconBase64: j['iconBase64']);
  factory CachedAppInfo.fromAppInfo(AppInfo a) => CachedAppInfo(
    name: a.name, packageName: a.packageName,
    iconBase64: (a.icon != null && a.icon!.isNotEmpty) ? base64Encode(a.icon!) : null,
  );
  Uint8List? get iconBytes => iconBase64 != null ? base64Decode(iconBase64!) : null;
}

class NotificationConfigScreen extends StatefulWidget {
  const NotificationConfigScreen({super.key});
  @override
  State<NotificationConfigScreen> createState() => _NotificationConfigScreenState();
}

class _NotificationConfigScreenState extends State<NotificationConfigScreen> {
  static const _kNameMapKey = "notif_name_map";
  static const _kHexMapKey = "notif_hex_map";
  static const _kShowSystemKey = "notif_show_system_apps";
  static const _kCachedKey = "cached_apps_list";
  static const _kCachedSysKey = "cached_apps_list_system";
  static const _kTsKey = "cached_apps_timestamp";
  static const _kTsSysKey = "cached_apps_timestamp_system";

  late final Future<DeviceConfig?> _cfgFuture;
  bool _showSystem = false, _reloading = false;
  List<CachedAppInfo> _apps = [];
  Map<String, String> _saved = {}, _working = {};
  bool _dirty = false;
  String _search = "";
  final _searchCtrl = TextEditingController();

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
    final j = sp.getString(sys ? _kCachedSysKey : _kCachedKey);
    if (j == null || j.isEmpty) return [];
    try { return (jsonDecode(j) as List).map((e) => CachedAppInfo.fromJson(e)).toList(); }
    catch (_) { return []; }
  }

  Future<void> _saveCache(List<CachedAppInfo> apps, bool sys) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(sys ? _kCachedSysKey : _kCachedKey, jsonEncode(apps.map((e) => e.toJson()).toList()));
    await sp.setInt(sys ? _kTsSysKey : _kTsKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> _stale(bool sys) async {
    final sp = await SharedPreferences.getInstance();
    final ts = sp.getInt(sys ? _kTsSysKey : _kTsKey);
    if (ts == null) return true;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)).inDays > 7;
  }

  Future<void> _reload({bool silent = false}) async {
    if (_reloading) return;
    if (!silent) setState(() => _reloading = true);
    try {
      final raw = await InstalledApps.getInstalledApps(
          excludeSystemApps: !_showSystem, excludeNonLaunchableApps: false, withIcon: true);
      final apps = raw.map((e) => CachedAppInfo.fromAppInfo(e)).toList();
      await _saveCache(apps, _showSystem);
      if (!mounted) return;
      setState(() { _apps = apps; _reloading = false; });
      if (!silent) {
        _showSnack('Loaded ${apps.length} apps');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _reloading = false);
      if (!silent) {
        _showSnack('Failed: $e', color: Colors.red[700]);
      }
    }
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
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
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kNameMapKey, jsonEncode(_working));
    final hex = <String, String>{};
    for (final e in _working.entries) {
      final h = cfg.ledEffects[e.value];
      if (h != null && h.trim().isNotEmpty) hex[e.key] = h;
    }
    await sp.setString(_kHexMapKey, jsonEncode(hex));
    if (!mounted) return;
    setState(() { _saved = Map.of(_working); _dirty = false; });
    _showSnack('Saved app LED patterns');
  }

  void _showSnack(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: color ?? const Color(0xFF1A2942),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft, radius: 1.4,
            colors: [Color(0xFF1e293b), Color(0xFF0f172a), Color(0xFF020617)],
          ),
        ),
        child: Column(children: [
          // ── Header
          ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16, right: 16, top: topPad > 0 ? 8 : 16, bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Padding(padding: const EdgeInsets.all(8),
                            child: Icon(Icons.arrow_back, color: Colors.white, size: 22)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text("App LED Sync",
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22))),
                        GestureDetector(
                          onTap: () => _reload(),
                          child: Padding(padding: const EdgeInsets.all(8),
                            child: _reloading
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))
                              : Icon(Icons.sync, color: kPrimary, size: 22)),
                        ),
                        GestureDetector(
                          onTap: _openSearch,
                          child: Padding(padding: const EdgeInsets.all(8),
                            child: Icon(Icons.more_vert, color: Colors.white, size: 22)),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // Search
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                          decoration: InputDecoration(
                            hintText: "Search installed apps...",
                            hintStyle: TextStyle(color: kTextDim, fontSize: 14),
                            prefixIcon: Icon(Icons.search, color: kTextDim),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // System toggle card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.settings_suggest_outlined, color: kPrimary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("System App Sync",
                                style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            Text("Include system applications in LED effects",
                                style: TextStyle(color: kTextDim, fontSize: 11)),
                          ])),
                          Switch(
                            value: _showSystem, onChanged: _toggleSystem,
                            activeThumbColor: kPrimary,
                            activeTrackColor: kPrimary.withValues(alpha: 0.3),
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),

          // ── App list
          Expanded(
            child: FutureBuilder<DeviceConfig?>(
              future: _cfgFuture,
              builder: (_, cfgSnap) {
                if (cfgSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: kPrimary));
                }
                final cfg = cfgSnap.data;
                if (cfg == null) {
                  return const Center(
                  child: Text("Device not supported", style: TextStyle(color: Color(0xFF8899AA))));
                }

                final effects = cfg.ledEffects;
                if (_apps.isEmpty && !_reloading) {
                  return const Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircularProgressIndicator(color: kPrimary),
                    SizedBox(height: 16),
                    Text("Loading apps...", style: TextStyle(color: Color(0xFF8899AA))),
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
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("INSTALLED APPS",
                          style: TextStyle(color: kTextDim, fontSize: 11,
                              fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      Text("${apps.length} Apps Found",
                          style: TextStyle(color: kTextDim, fontSize: 11)),
                    ]),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: apps.length,
                      itemBuilder: (_, i) => _appCard(apps[i], effects),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
      floatingActionButton: FutureBuilder<DeviceConfig?>(
        future: _cfgFuture,
        builder: (_, s) {
          final cfg = s.data;
          if (!_dirty || cfg == null) return const SizedBox.shrink();
          return FloatingActionButton(
            onPressed: () => _save(cfg),
            backgroundColor: kPrimary,
            shape: const CircleBorder(),
            child: const Icon(Icons.save_rounded, color: Colors.white, size: 28),
          );
        },
      ),
    );
  }

  Widget _appCard(CachedAppInfo app, Map<String, String> effects) {
    final sel = _working[app.packageName];
    final hasPattern = sel != null && sel.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hasPattern
                  ? kPrimary.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasPattern
                    ? kPrimary.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(children: [
              // App icon
              _appIcon(app.iconBytes),
              const SizedBox(width: 14),
              // App info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.name,
                    style: GoogleFonts.spaceGrotesk(
                        color: hasPattern ? Colors.white : Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(app.packageName,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              // Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hasPattern
                      ? kPrimary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasPattern
                        ? kPrimary.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: DropdownButton<String?>(
                  value: sel,
                  hint: Text("None (Disabled)", style: TextStyle(color: kTextDim, fontSize: 12)),
                  underline: const SizedBox(),
                  dropdownColor: const Color(0xFF1A2942),
                  isDense: true,
                  style: TextStyle(
                      color: hasPattern ? kPrimary : Colors.white,
                      fontSize: 12, fontWeight: FontWeight.w500),
                  icon: Icon(Icons.keyboard_arrow_down,
                      color: hasPattern ? kPrimary : kTextDim, size: 16),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None (Disabled)', style: TextStyle(color: kTextDim)),
                    ),
                    ...effects.keys
                        .map((n) => DropdownMenuItem<String?>(value: n, child: Text(n))),
                  ],
                  onChanged: (v) => setState(() {
                    _working = setOptionalMapping(_working, key: app.packageName, value: v);
                    _dirty = !_mapsEqual(_working, _saved);
                  }),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _appIcon(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.android, color: kTextDim, size: 28),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.memory(bytes, width: 50, height: 50,
          errorBuilder: (_, _, _) => Icon(Icons.android, color: kTextDim, size: 28)),
    );
  }

  Future<void> _openSearch() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        _searchCtrl.text = _search;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2942),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Search apps",
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _searchCtrl, autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Name or package…", hintStyle: TextStyle(color: kTextDim),
              prefixIcon: Icon(Icons.search, color: kTextDim),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kTextDim)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimary)),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null),
                child: Text("Cancel", style: TextStyle(color: kTextDim))),
            TextButton(onPressed: () => Navigator.pop(ctx, ""),
                child: Text("Clear", style: TextStyle(color: kTextDim))),
            TextButton(onPressed: () => Navigator.pop(ctx, _searchCtrl.text.trim()),
                child: const Text("Apply", style: TextStyle(color: kPrimary))),
          ],
        );
      },
    );
    if (!mounted || result == null) return;
    setState(() => _search = result.toLowerCase());
    _searchCtrl.text = result;
  }
}
