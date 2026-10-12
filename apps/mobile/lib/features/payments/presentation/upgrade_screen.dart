import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/entitlements.dart';
import '../domain/payment_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/presentation/coach_packages_view_sheet.dart';
import '../../../core/widgets/named_icon_button.dart';
import 'checkout_launcher.dart';

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);
const _amber  = Color(0xFFFFD479);

class _Plan {
  final ClientPlan plan;
  final String name, price, cadence, tagline;
  final List<String> features;
  final Color accent;
  final String? kind; // checkout kind, null for free / coach (marketplace)
  const _Plan(this.plan, this.name, this.price, this.cadence, this.tagline,
      this.features, this.accent, this.kind);
}

const _plans = [
  _Plan(ClientPlan.free, 'Free', '\$0', '', 'Build the habit',
      ['Community access', 'Recharge event registration', '4-week starter program',
       'Basic progress tracking', 'Limited nutrition tracking'],
      _muted, null),
  _Plan(ClientPlan.selfGuided, 'Self-Guided', '\$29', '/mo', 'Train on your terms',
      ['Full workout library', 'Full nutrition tracking', 'Habits & streaks',
       'Advanced analytics', 'Coach marketplace access'],
      _mint, 'self_guided'),
  _Plan(ClientPlan.aiGuided, 'AI-Guided', '\$59', '/mo', 'Your AI coach',
      ['Everything in Self-Guided', 'AI coaching & insights',
       'AI-generated programs', 'AI nutrition planning', 'Smart accountability'],
      _brand, 'ai_guided'),
  _Plan(ClientPlan.coachGuided, 'Coach-Guided', 'Coach-set', '', '1-on-1 with a real coach',
      ['Everything in AI-Guided', 'Dedicated human coach', 'Coach messaging',
       'Custom programming', 'Weekly check-in reviews'],
      _amber, null),
];

/// Module 16 — the upgrade paywall. Shows the Free → Self → AI → Coach ladder
/// with the user's current plan highlighted, and launches Stripe Checkout.
class UpgradeScreen extends ConsumerWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(clientPlanProvider);
    final current = currentAsync.valueOrNull ?? ClientPlan.free;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        // FIT-031 declares "Close" for this control. `AppBar`'s automatic
        // leading is a back arrow whose accessible name comes from Material's
        // default tooltip, not from the package — so it is replaced with the
        // declared word. The action is unchanged: it pops, exactly as before.
        leading: NamedIconButton(
          label: 'Close',
          onTap: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.close, color: _white, size: 20),
        ),
        title: const Text('Plans',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: _brand,
        backgroundColor: _card,
        onRefresh: () async => ref.invalidate(clientPlanProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text('Unlock your next level',
                style: TextStyle(
                    color: _white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Upgrade any time. Cancel any time.',
                style: TextStyle(color: _muted, fontSize: 14)),
            const SizedBox(height: 20),
            ..._plans.map((p) => _PlanCard(
                  plan: p,
                  isCurrent: p.plan == current,
                  current: current,
                )),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerStatefulWidget {
  final _Plan plan;
  final bool isCurrent;
  final ClientPlan current;
  const _PlanCard(
      {required this.plan, required this.isCurrent, required this.current});
  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  bool _loading = false;

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(clientPlanProvider);
    ref.invalidate(membershipTierProvider);
    ref.invalidate(mySubscriptionsProvider);
  }

  Future<void> _onCta() async {
    final p = widget.plan;
    final current = widget.current;
    // Capture ancestors up front so we never touch a defunct context after an
    // await (embedded checkout can navigate this screen away mid-flow).
    final messenger = ScaffoldMessenger.of(context);
    final paymentSvc = ref.read(paymentServiceProvider);

    // Coach-Guided is purchased per-coach via the marketplace.
    if (p.plan == ClientPlan.coachGuided) {
      context.push('/coach-marketplace');
      return;
    }

    // Downgrade to Free → cancel ALL active platform memberships.
    if (p.kind == null) {
      final subs = ref.read(mySubscriptionsProvider).valueOrNull ?? [];
      final memberships = subs
          .where((s) => ['self_guided', 'ai_guided'].contains(s['kind']) &&
              ['active', 'trialing', 'past_due'].contains(s['status']))
          .toList();
      if (memberships.isEmpty) return;
      final confirmed = await _confirmDowngradeToFree();
      if (confirmed != true) return;
      if (mounted) setState(() => _loading = true);
      for (final m in memberships) {
        await paymentSvc.cancelSubscription(m['id'] as String);
      }
      if (mounted) setState(() => _loading = false);
      _refresh();
      messenger.showSnackBar(
          const SnackBar(content: Text('Switched to the Free plan.')));
      return;
    }

    // Paid membership target.
    if (mounted) setState(() => _loading = true);
    final onMembership =
        current == ClientPlan.selfGuided || current == ClientPlan.aiGuided;
    if (onMembership) {
      final result = await paymentSvc.changeMembership(p.kind!);
      if (result == 'changed') {
        if (mounted) setState(() => _loading = false);
        _refresh();
        messenger.showSnackBar(
            SnackBar(content: Text('Your plan is now ${p.name}.')));
        return;
      }
      // 'needs_checkout' or 'error' → fall through to checkout.
    }
    // OWNER DIRECTION, 2026-10-12: do not create a new checkout session after
    // the client has navigated away from the upgrade flow.
    //
    // The gap this closes is the `await changeMembership` above. That call hits
    // the `update-subscription` function and returns one of 'changed',
    // 'needs_checkout' or 'error' — it creates NO session; 'needs_checkout' is a
    // signal that one is required. So returning here cannot abandon a session,
    // because at this point none exists. What it prevents is `startCheckout`
    // invoking `create-checkout` — which DOES mint a real session server-side —
    // on behalf of someone who already left.
    //
    // Deliberately NOT guarded: the case where the client leaves *during*
    // `startCheckout`. That session is already created and must not be
    // abandoned, so the call is allowed to finish and only the UI is skipped,
    // by the `!mounted` check immediately below. Cancelling mid-flight is what
    // would orphan a paid session.
    if (!mounted) return;
    final ok = await launchCheckout(context, ref, kind: p.kind!);
    if (!mounted) return; // embedded checkout navigated away; success screen refreshes
    setState(() => _loading = false);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not start checkout. Try again.')));
    }
    _refresh();
  }

  Future<bool?> _confirmDowngradeToFree() => showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Switch to Free?',
              style: TextStyle(color: _white, fontWeight: FontWeight.w800)),
          content: const Text(
            'Your paid features end immediately and the remaining period is not '
            'reimbursed. You can upgrade again any time.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Keep plan', style: TextStyle(color: _muted))),
            TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Switch to Free',
                    style: TextStyle(color: Color(0xFFFFB4AB), fontWeight: FontWeight.w700))),
          ],
        ),
      );

  String _ctaLabel() {
    final p = widget.plan;
    if (p.plan == ClientPlan.coachGuided) return 'Find a Coach';
    if (p.plan == ClientPlan.free) return 'Switch to Free';
    return p.plan.rank > widget.current.rank
        ? 'Upgrade to ${p.name}'
        : 'Switch to ${p.name}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final isCurrent = widget.isCurrent;

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
            color: isCurrent ? p.accent : p.accent.withValues(alpha: 0.25),
            width: isCurrent ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: p.accent.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 6))
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
                      style: TextStyle(
                          color: p.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text(p.tagline,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Current',
                      style: TextStyle(
                          color: p.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(p.price,
                        style: const TextStyle(
                            color: _white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    Text(p.cadence,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...p.features.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f,
                          style: const TextStyle(
                              color: _white, fontSize: 13)),
                    ),
                  ],
                ),
              )),
          // Coach-Guided current plan: let the client see their coach's
          // packages right here instead of navigating to the marketplace.
          if (isCurrent && p.plan == ClientPlan.coachGuided) ...[
            const SizedBox(height: 14),
            Builder(builder: (context) {
              final coach = ref.watch(assignedCoachProvider).valueOrNull;
              if (coach == null) return const SizedBox.shrink();
              final coachName =
                  '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
              final label = coachName.isEmpty
                  ? "View coach's packages"
                  : "View $coachName's packages";
              return SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.accent,
                    side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => showCoachPackagesSheet(
                      context, coach['id'] as String, coachName),
                ),
              );
            }),
          ],
          // Every non-current plan is actionable: upgrade, switch, or downgrade.
          if (!isCurrent) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      p.plan == ClientPlan.free ? _card : p.accent,
                  foregroundColor:
                      p.plan == ClientPlan.free ? _muted : Colors.black87,
                  side: p.plan == ClientPlan.free
                      ? const BorderSide(color: _muted)
                      : null,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : _onCta,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black87))
                    : Text(_ctaLabel(),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
