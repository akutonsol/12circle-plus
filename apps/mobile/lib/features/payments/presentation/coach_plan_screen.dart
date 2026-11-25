import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../data/payment_service.dart' show ownerGone, signedInUid;
import '../domain/payment_provider.dart';
import 'checkout_launcher.dart';
import 'upgrade_screen.dart' show PlanLoadingRow;

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);
const _amber  = Color(0xFFFFD479);

class _CoachPlan {
  final String tier, name, price, clients;
  final List<String> features;
  final Color accent;
  const _CoachPlan(this.tier, this.name, this.price, this.clients, this.features, this.accent);
}

const _coachPlans = [
  _CoachPlan('starter', 'Starter', '\$99', 'Up to 25 clients',
      ['Client management', 'Program & nutrition builder', 'Check-in reviews',
       'Compliance dashboard'], _mint),
  _CoachPlan('growth', 'Growth', '\$199', 'Up to 100 clients',
      ['Everything in Starter', 'Marketplace listing', 'Priority support',
       'Advanced client intelligence'], _brand),
  _CoachPlan('elite', 'Elite', '\$299', 'Unlimited clients',
      ['Everything in Growth', 'Unlimited roster', 'Featured marketplace placement',
       'Early access to new tools'], _amber),
];

/// Coach platform plans — the coach pays 12 Circle monthly (Starter/Growth/Elite).
/// Subscribing also raises the coach's client capacity (handled by the webhook).
class CoachPlanScreen extends ConsumerWidget {
  const CoachPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(paymentAccountProvider);
    // P0-FL-60a: this account's tier only (A-19), and an unread tier is not
    // "no plan": nothing is for sale until coach_plan_tier() has answered.
    final read = ref.watch(ownedCoachPlanTierProvider);
    final current = read.value;
    final canChoose = read.hasValue && read.error == null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: const Text('Your Plan',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: _brand,
        backgroundColor: _card,
        onRefresh: () async => ref.invalidate(coachPlanTierProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text('Coach on 12 Circle',
                style: TextStyle(color: _white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Keep 100% of clients you bring. Marketplace leads carry a small commission.',
                style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 20),
            if (read.error != null) ...[
              SectionLoadFailure(
                what: 'your plan',
                error: read.error,
                busy: read.isLoading,
                accent: _brand,
                detail: read.hasValue
                    ? 'This is the plan from the last time it loaded. '
                        'Plans can’t be chosen until it loads.'
                    : 'Plans can’t be chosen until it loads.',
                onRetry: () => ref.invalidate(coachPlanTierProvider),
              ),
              const SizedBox(height: 16),
            ] else if (!read.hasValue) ...[
              const PlanLoadingRow(),
              const SizedBox(height: 16),
            ],
            ..._coachPlans.map((p) => _CoachPlanCard(
                  key: ValueKey((account, p.tier)),
                  account: account,
                  plan: p,
                  isCurrent: read.hasValue && current == p.tier,
                  canChoose: canChoose,
                )),
          ],
        ),
      ),
    );
  }
}

class _CoachPlanCard extends ConsumerStatefulWidget {
  /// The account this card was built for (P0-FL-60a).
  final String? account;
  final _CoachPlan plan;
  final bool isCurrent;
  final bool canChoose;
  const _CoachPlanCard(
      {super.key,
      required this.account,
      required this.plan,
      required this.isCurrent,
      required this.canChoose});
  @override
  ConsumerState<_CoachPlanCard> createState() => _CoachPlanCardState();
}

class _CoachPlanCardState extends ConsumerState<_CoachPlanCard> {
  bool _loading = false;

  Future<void> _subscribe() async {
    final owner = widget.account;
    if (ownerGone(owner, 'CoachPlanScreen', 'choose a plan')) return;
    setState(() => _loading = true);
    // launchCheckout reports its own failure -- including "you already have a
    // coach plan", which a second checkout would have billed twice.
    await launchCheckout(context, ref, kind: 'coach_plan', tier: widget.plan.tier, owner: owner);
    // Left, or another account signed in (the card is keyed by account).
    if (!mounted) return;
    setState(() => _loading = false);
    // Another account's read is not this action's to refresh.
    if (signedInUid() != owner) return;
    ref.invalidate(coachPlanTierProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accent.withValues(alpha: 0.14), _card],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: widget.isCurrent ? p.accent : p.accent.withValues(alpha: 0.25),
            width: widget.isCurrent ? 2 : 1),
        boxShadow: [
          BoxShadow(color: p.accent.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: TextStyle(color: p.accent, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(p.clients, style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              if (widget.isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Current',
                      style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(p.price,
                        style: const TextStyle(color: _white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const Text('/mo', style: TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...p.features.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: const TextStyle(color: _white, fontSize: 13))),
                ]),
              )),
          if (!widget.isCurrent) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading || !widget.canChoose ? null : _subscribe,
                child: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                    : Text('Choose ${p.name}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
