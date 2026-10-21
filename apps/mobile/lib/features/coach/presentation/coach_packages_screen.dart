import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme/app_background.dart';
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
class CoachPackagesScreen extends ConsumerWidget {
  const CoachPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgsAsync = ref.watch(myPackagesProvider);
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
          onPressed: () => _edit(context, ref),
        ),
        body: pkgsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
          error: (e, _) => Center(child: Text('Could not load packages.',
              textAlign: TextAlign.center, style: const TextStyle(color: _muted))),
          data: (pkgs) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Text('Offer clients flexible ways to train with you. They’ll '
                  'see these when choosing you as their coach.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              _ConnectBanner(),
              const SizedBox(height: 4),
              if (pkgs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No packages yet — tap “New Package”.',
                      style: TextStyle(color: _muted))),
                ),
              ...pkgs.map((p) => _PackageCard(
                    pkg: p,
                    onEdit: () => _edit(context, ref, existing: p),
                    onDelete: () async {
                      await ref.read(packageServiceProvider).deletePackage(p['id'] as String);
                      ref.invalidate(myPackagesProvider);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, {Map<String, dynamic>? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PackageEditor(existing: existing),
    );
    if (saved == true) ref.invalidate(myPackagesProvider);
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
  bool _tiersLoaded = false;

  @override
  void initState() {
    super.initState();
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
    if (_tiersLoaded) return;
    _tiersLoaded = true;
    final tiers = await ref.read(packageServiceProvider).getSessionTiers();
    for (final t in PackageService.sessionTiers) {
      final d = tiers[t];
      if (d != null && d.price > 0) {
        _tierPrice[t]!.text = d.price.toStringAsFixed(0);
        _tierName[t]!.text = d.name;
        _tierDesc[t]!.text = d.description;
      }
    }
    if (mounted) setState(() {});
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
    setState(() => _saving = true);
    final svc = ref.read(packageServiceProvider);
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
        _fillChip('Use suggested prices', () => setState(() {
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

            if (isBulk) ...[
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
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _saving ? null : _save,
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
    final s = ref.watch(coachConnectStatusProvider).valueOrNull;
    final ready = s != null && s['connected'] == true && s['charges_enabled'] == true;
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
