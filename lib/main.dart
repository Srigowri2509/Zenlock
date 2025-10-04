import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ---------- PALETTE ----------
class AppColors {
  static const bg     = Color(0xFFF4F1DE); // cream
  static const ink    = Color(0xFF3D405B); // inky text
  static const accent = Color(0xFFE07A5F); // coral
  static const mint   = Color(0xFF81B29A); // mint
  static const card   = Colors.white;
  static const chipBg = Color(0xFFFFE8E1); // soft coral tint
}

/// ---------- THEME ----------
ThemeData zenTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.poppins(
        fontWeight: FontWeight.w700, fontSize: 22, color: AppColors.ink),
      iconTheme: const IconThemeData(color: AppColors.ink),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

/// ---------- MODEL ----------
class AppRule {
  final String packageName;
  final String appName;
  final DateTime lockedUntil;

  AppRule({
    required this.packageName,
    required this.appName,
    required this.lockedUntil,
  });

  Duration get remaining => lockedUntil.difference(DateTime.now());
  bool get active => remaining.inSeconds > 0;

  Map<String, dynamic> toJson() => {
        'package': packageName,
        'name': appName,
        'until': lockedUntil.millisecondsSinceEpoch,
      };

  static AppRule fromJson(Map<String, dynamic> j) => AppRule(
        packageName: j['package'],
        appName: j['name'],
        lockedUntil: DateTime.fromMillisecondsSinceEpoch(j['until']),
      );
}

/// ---------- STORAGE ----------
class RulesStore {
  static const _listKey = 'zenlock_rules';

  Future<List<AppRule>> read() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_listKey) ?? [];
    return raw.map((s) => AppRule.fromJson(jsonDecode(s))).toList();
  }

  Future<void> write(List<AppRule> rules) async {
    final sp = await SharedPreferences.getInstance();

    // Persist for Flutter UI
    await sp.setStringList(
      _listKey,
      rules.map((r) => jsonEncode(r.toJson())).toList(),
    );

    // Persist per-app deadlines so Kotlin can read them (RulesBridge)
    for (final r in rules) {
      await sp.setString(
        'lock_${r.packageName}', // Kotlin reads "flutter.lock_<package>"
        r.lockedUntil.millisecondsSinceEpoch.toString(),
      );
    }
  }
}

/// ---------- CONTROLLER ----------
class RulesController extends StateNotifier<List<AppRule>> {
  final RulesStore store;
  Timer? _ticker;

  RulesController(this.store) : super([]) {
    _init();
  }

  Future<void> _init() async {
    state = await store.read();
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now();
      final filtered = state.where((r) => r.lockedUntil.isAfter(now)).toList();
      if (filtered.length != state.length) {
        state = filtered;
        await store.write(state);
      } else {
        state = [...state]; // repaint countdowns
      }
    });
  }

  Future<void> addCooldown(String package, String name, Duration d) async {
    final until = DateTime.now().add(d);
    final updated = [...state, AppRule(packageName: package, appName: name, lockedUntil: until)];
    state = updated;
    await store.write(updated);
  }

  Future<void> removeRule(AppRule r) async {
    if (r.active) return; // block early unlocks
    final updated = [...state]..removeWhere((e) => e.packageName == r.packageName);
    state = updated;
    await store.write(updated);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final rulesProvider =
    StateNotifierProvider<RulesController, List<AppRule>>(
  (ref) => RulesController(RulesStore()),
);

/// ---------- MAIN ----------
void main() {
  runApp(const ProviderScope(child: ZenLockApp()));
}

class ZenLockApp extends StatelessWidget {
  const ZenLockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenLock',
      theme: zenTheme(),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

/// ---------- HOME ----------
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("ZenLock")),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _HeaderHero(),
          ),
          const SizedBox(height: 8),
          if (rules.isEmpty)
            const _EmptyState()
          else
            ...rules.map((r) => _LockCard(rule: r)),
          const SizedBox(height: 100),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final picked = await Navigator.of(context).push<AppInfo>(
            MaterialPageRoute(builder: (_) => const AppPickerPage()),
          );
          if (picked == null) return;

          final d = await showModalBottomSheet<Duration>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _DurationPickerSheet(),
          );
          if (d == null) return;

          await ref.read(rulesProvider.notifier).addCooldown(
                picked.packageName,
                picked.name,
                d,
              );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// ---------- HEADER ----------
class _HeaderHero extends StatelessWidget {
  const _HeaderHero();

  @override
  Widget build(BuildContext context) {
    return _Bubble(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF1EA), Color(0xFFEFD6CD), Color(0xFFF4F1DE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.mint.withOpacity(.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_clock, color: AppColors.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Stay in flow",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.ink)),
                  const SizedBox(height: 6),
                  Text("Lock distracting apps for a while. You can’t unlock early.",
                      style: GoogleFonts.poppins(
                        color: AppColors.ink.withOpacity(.75), fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- Bubble ----------
class _Bubble extends StatelessWidget {
  final Widget child;
  const _Bubble({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 8))],
        borderRadius: BorderRadius.circular(26),
      ),
      child: ClipPath(
        clipper: _BubbleClipper(),
        child: child,
      ),
    );
  }
}

class _BubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height, r = 24.0;
    final p = Path();
    p.moveTo(r, 0);
    p.cubicTo(w * .35, 8, w * .65, -8, w - r, 4);
    p.quadraticBezierTo(w, 6, w, r);
    p.cubicTo(w - 6, h * .35, w + 6, h * .65, w - 8, h - r);
    p.quadraticBezierTo(w - 6, h, w - r, h);
    p.cubicTo(w * .65, h - 8, w * .35, h + 8, r, h - 4);
    p.quadraticBezierTo(0, h - 6, 0, h - r);
    p.cubicTo(6, h * .65, -6, h * .35, 8, r);
    p.quadraticBezierTo(6, 0, r, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// ---------- Empty state ----------
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.self_improvement, color: AppColors.accent, size: 42),
          const SizedBox(height: 8),
          Text("Nothing locked yet",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text("Tap + to choose an app and set a timer.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: AppColors.ink.withOpacity(.7))),
        ],
      ),
    );
  }
}

/// ---------- App Icon (version-tolerant: uses only getInstalledApps) ----------
class _AppIcon extends StatefulWidget {
  final String package;
  final String fallbackLetter;
  const _AppIcon({required this.package, required this.fallbackLetter});

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // installed_apps 1.6.0 signature: getInstalledApps(bool excludeSystemApps, bool withIcon)
      final apps = await InstalledApps.getInstalledApps(true, true);
      AppInfo? match;
      for (final a in apps) {
        if (a.packageName == widget.package) {
          match = a;
          break;
        }
      }
      if (!mounted) return;
      if (match != null && match.icon != null && match.icon!.isNotEmpty) {
        setState(() => bytes = match!.icon);
      }
    } catch (_) {
      // leave bytes = null -> fallback letter avatar
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bytes != null && bytes!.isNotEmpty) {
      return CircleAvatar(radius: 22, backgroundImage: MemoryImage(bytes!));
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.mint.withOpacity(.25),
      child: Text(widget.fallbackLetter,
          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700)),
    );
  }
}

/// ---------- Lock card ----------
class _LockCard extends ConsumerWidget {
  final AppRule rule;
  const _LockCard({required this.rule});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return "$h:${two(m)}:${two(s)}";
    return "${two(m)}:${two(s)}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letter = rule.appName.isNotEmpty ? rule.appName[0].toUpperCase() : "?";
    final locked = rule.active;

    return _Bubble(
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top row
            Row(
              children: [
                _AppIcon(package: rule.packageName, fallbackLetter: letter),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rule.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(children: [
                    const Icon(Icons.timer, size: 16, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text(_fmt(rule.remaining),
                        style: const TextStyle(
                          color: AppColors.accent, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // bottom row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.mint.withOpacity(.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text("Locked",
                      style: TextStyle(
                        color: AppColors.ink, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                if (locked)
                  const Icon(Icons.block, size: 18, color: AppColors.accent),
                if (locked) const SizedBox(width: 6),
                if (locked)
                  Flexible(
                    child: Text(
                      "cannot unlock until timer ends",
                      style: TextStyle(color: AppColors.accent.withOpacity(.95)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                const Spacer(),
                // Remove button only when unlocked (timer done)
                Opacity(
                  opacity: locked ? 0.3 : 1,
                  child: TextButton.icon(
                    onPressed: locked
                        ? null
                        : () => ref.read(rulesProvider.notifier).removeRule(rule),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Remove"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- Duration picker (chips + HH:MM:SS custom) ----------
class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet();
  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  Duration? _selected;
  final _hCtl = TextEditingController(text: "0");
  final _mCtl = TextEditingController(text: "0");
  final _sCtl = TextEditingController(text: "0");

  int _parse(String v, int max) {
    final n = int.tryParse(v.trim()) ?? 0;
    return n.clamp(0, max).toInt(); // clamp returns num => cast to int
  }

  Widget _chip(String label, Duration d) => ChoiceChip(
        label: Text(label),
        selected: _selected == d,
        onSelected: (_) => setState(() => _selected = d),
        selectedColor: AppColors.chipBg,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 24)],
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42, height: 5,
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 12),
            Text("Lock duration",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              _chip("10m", const Duration(minutes: 10)),
              _chip("20m", const Duration(minutes: 20)),
              _chip("30m", const Duration(minutes: 30)),
              _chip("1h", const Duration(hours: 1)),
              _chip("2h", const Duration(hours: 2)),
              _chip("4h", const Duration(hours: 4)),
            ]),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: TextField(
                  controller: _hCtl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Hours"),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _mCtl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Minutes"),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _sCtl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Seconds"),
                )),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Duration? d = _selected;
                  final h = _parse(_hCtl.text, 99);
                  final m = _parse(_mCtl.text, 59);
                  final s = _parse(_sCtl.text, 59);
                  final custom = Duration(hours: h, minutes: m, seconds: s);
                  if (custom.inSeconds > 0) d = custom;
                  if (d == null) return;
                  Navigator.pop(context, d);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                child: const Text("Start Lock", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- App picker (with real icons + search) ----------
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key});
  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<AppInfo> _apps = [], _filtered = [];
  final _searchCtl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtl.addListener(() {
      final q = _searchCtl.text.toLowerCase();
      setState(() {
        _filtered = _apps.where((a) =>
          a.name.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q)).toList();
      });
    });
  }

  Future<void> _load() async {
    // installed_apps 1.6.0: getInstalledApps(excludeSystemApps, withIcon)
    final all = await InstalledApps.getInstalledApps(true, true);
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _apps = all;
      _filtered = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select app")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchCtl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: "Search apps",
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final app = _filtered[i];
                      final iconBytes = app.icon;
                      final ImageProvider<Object>? iconProvider =
                          (iconBytes != null && iconBytes.isNotEmpty) ? MemoryImage(iconBytes) : null;

                      return _Bubble(
                        child: Container(
                          color: AppColors.card,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.mint.withOpacity(.2),
                              backgroundImage: iconProvider,
                              child: iconProvider == null
                                  ? Text(app.name.isNotEmpty ? app.name[0].toUpperCase() : "?",
                                      style: const TextStyle(color: AppColors.ink))
                                  : null,
                            ),
                            title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(app.packageName,
                                style: const TextStyle(color: Colors.black45)),
                            onTap: () => Navigator.pop(context, app),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
