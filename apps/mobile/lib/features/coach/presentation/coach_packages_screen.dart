import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/observability/app_failure.dart';
import '../../../shared/theme/app_background.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../../payments/domain/payment_provider.dart';
import '../data/package_service.dart';
import '../domain/package_provider.dart';

const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);
const _amber  = Color(0xFFFFD479);
const _sky    = Color(0xFF7FD1FF);
const _rose   = Color(0xFFFF9FB0);

// The 5 service types a coach can offer.
const _serviceTypes = ['per_session', 'bulk', 'monthly', 'hybrid', 'consultation'];

String _typeLabel(String t) => switch (t) {
      'per_session' => 'Single Session',
      'bulk' => 'Session Package',
      'monthly' => 'Monthly Membership',
      'hybrid' => 'Hybrid Membership',
      'consultation' => 'Consultation',
      _ => t,
    };
Color _typeColor(String t) => switch (t) {
      'per_session' => _mint,
      'bulk' => _amber,
      'monthly' => _brand,
      'hybrid' => _sky,
      'consultation' => _rose,
      _ => _brand,
    };
bool _isRecurring(String t) => t == 'monthly' || t == 'hybrid';

/// Coach defines the packages they offer clients: pay-per-session, bulk session
/// packages (any number, each with its own session count + price), and monthly.
class CoachPackagesScreen extends ConsumerStatefulWidget {
  const CoachPackagesScreen({super.key});
  @override
  ConsumerState<CoachPackagesScreen> createState() => _CoachPackagesScreenState();
}

class _CoachPackagesScreenState extends ConsumerState<CoachPackagesScreen> {
  /// P0-FL-56b: the last answer read for [_for], the coach signed in now. A
  /// failed re-read keeps it on screen; another coach never sees it (Riverpod
  /// itself keeps the previous value through a sign-in switch).
  String? _for;
  List<Map<String, dynamic>>? _kept;
  Object? _loadError;

  /// Packages with a delete in flight: a second delete of the same one would
  /// match no row and be said as a failure.
  final Set<String> _deleting = {};

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserProvider)?.id;
    final pkgsAsync = ref.watch(myPackagesProvider);
    if (_for != uid) {
      _for = uid;
      _kept = null;
      _loadError = null;
    }
    if (!pkgsAsync.isLoading) {
      _loadError = pkgsAsync.error;
      if (!pkgsAsync.hasError) _kept = pkgsAsync.value;
    }
    final pkgs = _kept;
    final failure = _loadError == null
        ? null
        : SectionLoadFailure(
            what: 'your packages',
            error: _loadError,
            busy: pkgsAsync.isLoading,
            onRetry: () => ref.invalidate(myPackagesProvider),
            accent: _brand,
            textColor: _white,
            mutedColor: _muted,
            detail: pkgs == null ? null : 'The list below may be out of date.',
          );
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: _white),
          title: const Text('Coaching Packages',
              style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _brand,
          icon: const Icon(Icons.add, color: _white),
          label: const Text('New Package', style: TextStyle(color: _white)),
          onPressed: () => _edit(),
        ),
        body: pkgs == null && failure == null
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : pkgs == null
          ? ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 96), children: [failure!])
          : ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Text('Offer clients flexible ways to train with you. They’ll '
                  'see these when choosing you as their coach.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              _ConnectBanner(),
              const SizedBox(height: 4),
              if (failure != null) ...[failure, const SizedBox(height: 8)],
              if (pkgs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No packages yet — tap “New Package”.',
                      style: TextStyle(color: _muted))),
                ),
              ...pkgs.map((p) => _PackageCard(
                    pkg: p,
                    onEdit: () => _edit(existing: p),
                    onDelete: () => _delete(p['id'] as String),
                  )),
            ],
          ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    if (!_deleting.add(id)) return;
    final owner = _for;
    // P0-FL-53b · a failed delete escaped unhandled: no message, the package
    // simply stayed. Recorded and said.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(packageServiceProvider).deletePackage(id);
    } catch (e, st) {
      reportError('CoachPackagesScreen.deletePackage', e, st);
      // Left, or another coach signed in: not theirs to hear.
      if (!mounted || _for != owner) return;
      messenger.showSnackBar(SnackBar(content: Semantics(
          liveRegion: true,
          child: Text(couldntMessage('delete this package', e)))));
      // No row matched: the package may already be gone, so re-read the list.
      if (e is PackageNotChanged) ref.invalidate(myPackagesProvider);
      return;
    } finally {
      _deleting.remove(id);
    }
    if (mounted) ref.invalidate(myPackagesProvider);
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PackageEditor(existing: existing),
    );
    if (saved == true && mounted) ref.invalidate(myPackagesProvider);
  }
}

class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> pkg;
  final VoidCallback onEdit, onDelete;
  const _PackageCard({required this.pkg, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final type = pkg['type'] as String? ?? 'monthly';
    final color = _typeColor(type);
    final price = (pkg['price'] as num?)?.toDouble() ?? 0;
    final sessions = (pkg['sessions'] as num?)?.toInt() ?? 0;
    final per = _isRecurring(type) ? '/mo' : type == 'per_session' ? '/session' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.12), _card]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Text(_typeLabel(type),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text(pkg['name'] as String? ?? '',
              style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
          if (type == 'bulk') Text('$sessions sessions',
              style: const TextStyle(color: _muted, fontSize: 12)),
          if (type == 'hybrid' && sessions > 0) Text('$sessions sessions/mo included',
              style: const TextStyle(color: _muted, fontSize: 12)),
          if ((pkg['description'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 2),
            Text(pkg['description'] as String, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
          // A delete the database refused (a client's schedule uses the package)
          // hides it instead; without this the card looked untouched.
          if (pkg['active'] == false) ...[
            const SizedBox(height: 2),
            const Text('Hidden from clients',
                style: TextStyle(color: _amber, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${price.toStringAsFixed(0)}$per',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          PopupMenuButton<String>(
            color: _card,
            icon: const Icon(Icons.more_horiz, color: _muted),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: _white))),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Color(0xFFFFB4AB)))),
            ],
          ),
        ]),
      ]),
    );
  }
}

class _PackageEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const _PackageEditor({this.existing});
  @override
  ConsumerState<_PackageEditor> createState() => _PackageEditorState();
}

class _PackageEditorState extends ConsumerState<_PackageEditor> {
  late String _type;
  late TextEditingController _name, _price, _desc, _sessions, _cancel;
  // Session-package tiers (4/8/12/16) — each independently named/priced.
  final Map<int, TextEditingController> _tierName = {
    for (final t in PackageService.sessionTiers) t: TextEditingController(),
  };
  final Map<int, TextEditingController> _tierPrice = {
    for (final t in PackageService.sessionTiers) t: TextEditingController(),
  };
  final Map<int, TextEditingController> _tierDesc = {
    for (final t in PackageService.sessionTiers) t: TextEditingController(),
  };
  bool _saving = false;
  /// The last save's failure, said above the Save button (P0-FL-53b r2).
  String? _error;
  /// P0-FL-56b: the coach's current tiers were read (a genuine "none yet"
  /// included). Until then the tier fields and Save are not offered: a blank
  /// price means "don't offer", so saving unread tiers would remove them all.
  bool _tiersReady = false;
  bool _tiersLoading = false;
  Object? _tiersError;

  /// The coach this editor was opened for. If another signs in, it is dropped.
  String? _owner;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentUserProvider)?.id;
    final e = widget.existing;
    _type = e?['type'] as String? ?? 'per_session';
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    _price = TextEditingController(text: ((e?['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _desc = TextEditingController(text: e?['description'] as String? ?? '');
    _sessions = TextEditingController(
        text: ((e?['sessions'] as num?)?.toInt() ?? 0) > 0 ? '${(e?['sessions'] as num).toInt()}' : '');
    _cancel = TextEditingController(text: e?['cancellation_policy'] as String? ?? '');
    if (_type == 'bulk') _loadTiers();
  }

  Future<void> _loadTiers() async {
    if (_tiersReady || _tiersLoading) return;
    _tiersLoading = true;
    final Map<int, ({String name, double price, String description})> tiers;
    try {
      tiers = await ref.read(packageServiceProvider).getSessionTiers();
    } catch (e, st) {
      reportError('CoachPackagesScreen._PackageEditor._loadTiers', e, st);
      if (!mounted) return;
      setState(() {
        _tiersLoading = false;
        _tiersError = e;
      });
      return;
    }
    if (!mounted) return;
    for (final t in PackageService.sessionTiers) {
      final d = tiers[t];
      if (d != null && d.price > 0) {
        _tierPrice[t]!.text = d.price.toStringAsFixed(0);
        _tierName[t]!.text = d.name;
        _tierDesc[t]!.text = d.description;
      }
    }
    setState(() {
      _tiersLoading = false;
      _tiersError = null;
      _tiersReady = true;
    });
  }

  @override
  void dispose() {
    _name.dispose(); _price.dispose(); _desc.dispose(); _sessions.dispose(); _cancel.dispose();
    for (final c in _tierName.values) c.dispose();
    for (final c in _tierPrice.values) c.dispose();
    for (final c in _tierDesc.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || (_type == 'bulk' && !_tiersReady)) return;
    if (ref.read(currentUserProvider)?.id != _owner) return;
    setState(() { _saving = true; _error = null; });
    final svc = ref.read(packageServiceProvider);
    // P0-FL-53b · a failed save escaped unhandled: the button spun for good
    // and nothing was said. Now it is recorded and said, and the sheet stays
    // open with what the coach typed.
    try {
    if (_type == 'bulk') {
      final tiers = <int, ({String name, double price, String description})>{
        for (final t in PackageService.sessionTiers)
          t: (
            name: _tierName[t]!.text.trim(),
            price: double.tryParse(_tierPrice[t]!.text.trim()) ?? 0,
            description: _tierDesc[t]!.text.trim(),
          ),
      };
      await svc.saveSessionTiers(tiers);
    } else {
      if (_name.text.trim().isEmpty) { if (mounted) setState(() => _saving = false); return; }
      await svc.savePackage(
        id: widget.existing?['id'] as String?,
        type: _type,
        name: _name.text.trim(),
        sessions: _type == 'per_session'
            ? 1
            : _type == 'hybrid'
                ? (int.tryParse(_sessions.text.trim()) ?? 0)
                : 0,
        price: double.tryParse(_price.text.trim()) ?? 0,
        description: _desc.text.trim(),
        cancellationPolicy: _cancel.text.trim().isEmpty ? null : _cancel.text.trim(),
      );
    }
    } catch (e, st) {
      reportError('CoachPackagesScreen._PackageEditor._save', e, st);
      if (!mounted) return;
      // Some tiers were changed before one failed (P0-FL-56b): say which, and
      // re-read the list under this sheet, which now differs.
      if (e is SessionTiersPartlySaved) ref.invalidate(myPackagesProvider);
      // Said inside the sheet: a SnackBar would sit on the Scaffold under it.
      setState(() {
        _saving = false;
        _error = e is SessionTiersPartlySaved
            ? 'Only part of this was saved: your changes to the '
                '${_packs(e.saved)} are saved. '
                '${couldntMessage('save the ${_packs(e.notSaved)}', e.cause)}'
            : couldntMessage('save this package', e);
      });
      return;
    }
    if (mounted) { setState(() => _saving = false); Navigator.pop(context, true); }
  }

  // ── Type-specific pricing recommendations (premium positioning) ──
  Widget _recommendation() {
    final children = <Widget>[
      const Row(children: [
        Icon(Icons.auto_awesome_rounded, color: _brand, size: 16),
        SizedBox(width: 6),
        Text('Suggested for 12 Circle',
            style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 8),
    ];

    if (_type == 'per_session') {
      children.addAll([
        const Text('Position coaching as premium. Most coaches start at \$99 for a '
            '60-min session (goal review, workout guidance, progress recommendations).',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        const SizedBox(height: 6),
        const Text('Entry \$75–100  ·  Experienced \$100–150  ·  Elite \$150–250+',
            style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 10),
        _fillChip('Use \$99', () => setState(() => _price.text = '99')),
      ]);
    } else if (_type == 'monthly') {
      children.addAll([
        const Text('Recurring memberships are your strongest revenue. Tap a tier to '
            'pre-fill name, price & what’s included — then tweak:',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _tierTemplate('Basic Accountability', 199,
              'Custom workout program · Messaging · Monthly check-in · Progress tracking'),
          _tierTemplate('Premium Coaching', 299,
              'Personalized programming · Nutrition guidance · Weekly check-ins · Unlimited messaging · Habit coaching'),
          _tierTemplate('VIP Coaching', 499,
              'Full programming · Nutrition coaching · Weekly reviews · Priority support · Video form reviews · Goal strategy'),
        ]),
      ]);
    } else if (_type == 'hybrid') {
      children.addAll([
        const Text('Hybrid memberships bundle a recurring program with a set number '
            'of live sessions each month — your highest-value offer. Set the monthly '
            'price and how many sessions are included:',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _hybridTemplate('Hybrid Essentials', 399, 2,
              'Custom program · Nutrition guidance · 2 live sessions/mo · Unlimited messaging'),
          _hybridTemplate('Hybrid Premium', 699, 4,
              'Full programming · Nutrition coaching · 4 live sessions/mo · Weekly reviews · Priority support'),
        ]),
      ]);
    } else if (_type == 'consultation') {
      children.addAll([
        const Text('A one-time consultation is a low-friction entry point — a goal & '
            'strategy call that converts clients into ongoing coaching. Keep it '
            'accessible:',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        const SizedBox(height: 6),
        const Text('Intro \$0–49  ·  Strategy session \$49–99  ·  Deep-dive \$99–149',
            style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 10),
        _fillChip('Use \$49', () => setState(() => _price.text = '49')),
      ]);
    } else {
      children.addAll([
        const Text('Bigger bundles = better per-session value for clients (premium '
            'positioning, but a volume discount):',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        const SizedBox(height: 6),
        const Text('4 → \$399 (\$99.75/ea)  ·  8 → \$749 (\$93.63/ea)\n'
            '12 → \$1,099 (\$91.58/ea)  ·  16 → \$1,399 (\$87.44/ea)',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 10),
        if (_tiersReady) _fillChip('Use suggested prices', () => setState(() {
          _tierPrice[4]!.text = '399'; _tierPrice[8]!.text = '749';
          _tierPrice[12]!.text = '1099'; _tierPrice[16]!.text = '1399';
        })),
      ]);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _fillChip(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _brand.withValues(alpha: 0.4)),
          ),
          child: Text(label,
              style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _tierTemplate(String name, int price, String includes) => GestureDetector(
        onTap: () => setState(() {
          _name.text = name;
          _price.text = '$price';
          _desc.text = includes;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _brand.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w700)),
            Text('\$$price/mo', style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _hybridTemplate(String name, int price, int sessions, String includes) => GestureDetector(
        onTap: () => setState(() {
          _name.text = name;
          _price.text = '$price';
          _sessions.text = '$sessions';
          _desc.text = includes;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _sky.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _sky.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w700)),
            Text('\$$price/mo · $sessions sessions', style: const TextStyle(color: _sky, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isBulk = _type == 'bulk';
    // Another coach signed in under this sheet: nothing of the first coach's is
    // shown, and the sheet goes.
    ref.listen(currentUserProvider, (_, user) {
      final route = ModalRoute.of(context);
      if (user?.id != _owner && route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
    if (ref.watch(currentUserProvider)?.id != _owner) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)))),
            Text(widget.existing == null ? 'New Package' : 'Edit Package',
                style: const TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text('Type', style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: _serviceTypes.map((t) =>
              ChoiceChip(
                label: Text(_typeLabel(t)),
                selected: _type == t,
                onSelected: (_) {
                  setState(() => _type = t);
                  if (t == 'bulk') _loadTiers();
                },
                backgroundColor: const Color(0xFF050309),
                selectedColor: _brand,
                labelStyle: TextStyle(color: _type == t ? _white : _muted, fontSize: 12),
                side: const BorderSide(color: _border),
              )).toList()),
            const SizedBox(height: 14),

            // Intelligent, type-specific pricing guidance.
            _recommendation(),

            if (isBulk && !_tiersReady) ...[
              if (_tiersError != null)
                SectionLoadFailure(
                  what: 'your session packages',
                  error: _tiersError,
                  busy: _tiersLoading,
                  onRetry: () => setState(() { _loadTiers(); }),
                  accent: _brand,
                  textColor: _white,
                  mutedColor: _muted,
                  detail: 'Saving is paused until they load.',
                )
              else
                const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: _brand, semanticsLabel: 'Loading your session packages'))),
            ] else if (isBulk) ...[
              const Text('Configure each bundle independently — its own name, price '
                  'and description. Leave a bundle’s price blank to not offer it.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              ...PackageService.sessionTiers.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF050309),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _amber.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _amber.withValues(alpha: 0.3))),
                      child: Text('$t SESSIONS',
                          style: const TextStyle(color: _amber, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _tierPrice[t],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: _white, fontWeight: FontWeight.w800, fontSize: 16),
                        decoration: const InputDecoration(
                          prefixText: '\$ ', prefixStyle: TextStyle(color: _white, fontWeight: FontWeight.w800),
                          hintText: 'Price', hintStyle: TextStyle(color: Color(0xFF6B6478)),
                          isDense: true, border: InputBorder.none),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _tierField(_tierName[t]!, 'Name (e.g. Starter Pack)'),
                  const SizedBox(height: 6),
                  _tierField(_tierDesc[t]!, 'Description (optional)', maxLines: 2),
                ]),
              )),
            ] else ...[
              _field('Name', _name, hint: 'e.g. ${_typeLabel(_type)}'),
              _field(
                  _isRecurring(_type)
                      ? 'Price (\$/month)'
                      : _type == 'consultation'
                          ? 'Price (\$/consultation)'
                          : 'Price (\$/session)',
                  _price, keyboard: TextInputType.number),
              if (_type == 'hybrid')
                _field('Sessions included per month', _sessions,
                    hint: 'e.g. 4', keyboard: TextInputType.number),
              _field('Included features', _desc,
                  hint: 'What the client gets', maxLines: 2),
              _field('Cancellation policy (optional)', _cancel,
                  hint: _isRecurring(_type)
                      ? 'e.g. Cancel anytime, effective next billing cycle'
                      : 'e.g. 24-hour notice for a full refund',
                  maxLines: 2),
            ],

            const SizedBox(height: 16),
            if (_error != null) ...[
              Semantics(liveRegion: true, child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, height: 1.35))),
              const SizedBox(height: 12),
            ],
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _saving || (isBulk && !_tiersReady) ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _white))
                  : Text(isBulk ? 'Save session packages' : 'Save package',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }
}

/// "4-session package", "4- and 8-session packages",
/// "4-, 8- and 12-session packages".
String _packs(List<int> tiers) {
  final t = [for (final x in tiers) '$x-'];
  final list = t.length < 2
      ? t.join()
      : '${t.sublist(0, t.length - 1).join(', ')} and ${t.last}';
  return '${list}session package${t.length == 1 ? '' : 's'}';
}

// Compact field used inside a session-tier card.
Widget _tierField(TextEditingController c, String hint, {int maxLines = 1}) => TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: _white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6B6478), fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF0E0B16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _brand)),
      ),
    );

Widget _field(String label, TextEditingController c, {String? hint, int maxLines = 1, TextInputType? keyboard}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: c, maxLines: maxLines, keyboardType: keyboard,
          style: const TextStyle(color: _white),
          decoration: InputDecoration(
            hintText: hint, hintStyle: const TextStyle(color: Color(0xFF6B6478)),
            isDense: true, filled: true, fillColor: const Color(0xFF050309),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _brand)),
          ),
        ),
      ]),
    );

// Prompts the coach to connect Stripe before they can actually get paid.
class _ConnectBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(coachConnectStatusProvider);
    // Unknown (still reading, or the read failed) is not "not connected": only
    // a status that says so prompts the coach to connect (EC-14). AsyncData
    // only: a re-read for another coach still carries the previous coach's
    // status, as does its failure (P0-FL-56b).
    final s = status is AsyncData<Map<String, dynamic>> ? status.value : null;
    if (s == null) return const SizedBox.shrink();
    final ready = s['connected'] == true && s['charges_enabled'] == true;
    if (ready) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => context.push('/coach-payments'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD479).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD479).withValues(alpha: 0.4)),
        ),
        child: Row(children: const [
          Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFFFD479), size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Connect your Stripe account to receive payments for these packages.',
            style: TextStyle(color: Color(0xFFCFC2D6), fontSize: 12, height: 1.4))),
          Icon(Icons.chevron_right_rounded, color: Color(0xFFFFD479), size: 20),
        ]),
      ),
    );
  }
}
