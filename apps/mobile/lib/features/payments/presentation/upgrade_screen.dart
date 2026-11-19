import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/entitlements.dart';
import '../domain/payment_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/presentation/coach_packages_view_sheet.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
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
    reportPlanReadFailure(ref, 'UpgradeScreen.clientPlan');
    // P0-FL-17: an unread plan is not Free. Until client_plan() has answered,
    // no card is "Current" and nothing can be bought or switched — a coached
    // client was offered the plan they already had as if it were new.
    final current = knownPlan(currentAsync);

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
            if (current == null) ...[
              if (currentAsync.hasError)
                PlanLoadFailedNotice(
                  error: currentAsync.error!,
                  busy: currentAsync.isLoading,
                  detail: "Plans can't be changed until it loads.",
                  onRetry: () => ref.invalidate(clientPlanProvider),
                )
              else
                const PlanLoadingRow(),
              const SizedBox(height: 16),
            ],
            ..._plans.map((p) => _PlanCard(
                  plan: p,
                  isCurrent: current != null && p.plan == current,
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
  /// Null while the plan is unknown: every action is disabled.
  final ClientPlan? current;
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
      // Awaited: nothing on this screen watches the subscriptions, so
      // `valueOrNull` was null until another screen had read them, and the tap
      // found no membership and did nothing.
      final List<Map<String, dynamic>> subs;
      try {
        subs = await ref.read(mySubscriptionsProvider.future);
      } catch (_) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not cancel. Try again.')));
        return;
      }
      if (!mounted) return;
      final memberships = subs
          .where((s) => ['self_guided', 'ai_guided'].contains(s['kind']) &&
              ['active', 'trialing', 'past_due'].contains(s['status']))
          .toList();
      if (memberships.isEmpty) return;
      final confirmed = await _confirmDowngradeToFree();
      if (confirmed != true) return;
      if (mounted) setState(() => _loading = true);
      // The message follows what happened, as /manage-subscription's does: a
      // failed cancellation left the client billed and was announced as Free.
      var allOk = true;
      for (final m in memberships) {
        if (!await paymentSvc.cancelSubscription(m['id'] as String)) allOk = false;
      }
      if (mounted) setState(() => _loading = false);
      _refresh();
      messenger.showSnackBar(SnackBar(content: Text(
          allOk ? 'Switched to the Free plan.' : 'Could not cancel. Try again.')));
      return;
    }

    // Paid membership target. Always ask the server to change an existing
    // membership in place first -- whatever plan this screen shows: a member
    // who also has a coach shows as Coach-Guided while a membership still bills,
    // and skipping this sent them to buy a SECOND membership.
    if (mounted) setState(() => _loading = true);
    final result = await paymentSvc.changeMembership(p.kind!);
    if (result == 'changed') {
      if (mounted) setState(() => _loading = false);
      _refresh();
      messenger.showSnackBar(
          SnackBar(content: Text('Your plan is now ${p.name}.')));
      return;
    }
    // Only an explicit "there is no membership to change" may lead to a new
    // checkout. An error used to fall through to one too -- including when the
    // swap had gone through at Stripe and only the reply was lost: two
    // memberships, both billed.
    if (result != 'needs_checkout') {
      if (mounted) setState(() => _loading = false);
      messenger.showSnackBar(SnackBar(content: Text(result == 'payment_issue'
          ? 'Your current membership has a payment problem. Update your '
              'payment method in Billing, then change your plan.'
          : "Couldn't change your plan. Try again.")));
      _refresh();
      return;
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
    // launchCheckout reports its own failure (one message, the server's reason
    // when it refused a duplicate).
    await launchCheckout(context, ref, kind: p.kind!);
    if (!mounted) return; // embedded checkout navigated away; success screen refreshes
    setState(() => _loading = false);
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
    final current = widget.current;
    if (current == null) return 'Choose ${p.name}';
    return p.plan.rank > current.rank
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
                onPressed:
                    _loading || widget.current == null ? null : _onCta,
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

// ── Unknown plan (P0-FL-17) ─────────────────────────────────────────────────
// Shared by the plan screens (Plans, Subscription, Manage subscription, and
// the Profile and Settings rows). They live in this file only because the
// package that added them was limited to those five screens; nothing here
// depends on the rest of the file.

/// The plan client_plan() answered, or null while it is unknown (the first
/// read in flight, or it failed). A refresh that fails after a successful read
/// keeps the last real answer, as Riverpod does.
ClientPlan? knownPlan(AsyncValue<ClientPlan> plan) =>
    plan.hasValue ? plan.value : null;

/// "Couldn't load your plan — check your connection and try again."
const kPlanLoadOfflineMessage =
    "Couldn't load your plan — check your connection and try again.";

/// The non-network wording.
const kPlanLoadFailedMessage =
    "Couldn't load your plan — try again in a moment. "
    'If it keeps happening, contact support.';

/// The connection hint only for a network failure.
String planLoadFailedMessage(Object error) =>
    isNetworkFailure(error) ? kPlanLoadOfflineMessage : kPlanLoadFailedMessage;

/// Records a failed client_plan() read once per failure — on the transition
/// into a settled error, not on every rebuild that shows it. Call from build.
void reportPlanReadFailure(WidgetRef ref, String origin) {
  ref.listen<AsyncValue<ClientPlan>>(clientPlanProvider, (previous, next) {
    final settled = next.hasError &&
        !next.isLoading &&
        (previous == null || previous.isLoading || !previous.hasError);
    if (settled) reportError(origin, next.error!, next.stackTrace);
  });
}

/// The first plan read is in flight: a neutral line, never a plan name.
class PlanLoadingRow extends StatelessWidget {
  const PlanLoadingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Loading your plan',
      child: const ExcludeSemantics(
        child: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _muted)),
          SizedBox(width: 10),
          Text('Loading your plan…',
              style: TextStyle(color: _muted, fontSize: 13)),
        ]),
      ),
    );
  }
}

/// The plan could not be read: say so, say what is held back ([detail]) and
/// offer Try again. A live region; Try again is busy-aware (disabled and
/// "Loading…" while [busy], so it cannot fire twice), at least 44px tall, and
/// labelled for a screen reader.
class PlanLoadFailedNotice extends StatelessWidget {
  const PlanLoadFailedNotice({
    super.key,
    required this.error,
    required this.busy,
    required this.onRetry,
    this.detail,
  });

  final Object error;
  final bool busy;
  final VoidCallback onRetry;
  final String? detail;

  static const _red = Color(0xFFFFB4AB);
  static const _text = Color(0xFFE5E2E3);
  static const _link = Color(0xFFDDB7FF);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: _red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(planLoadFailedMessage(error),
                  style: const TextStyle(
                      color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!,
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: TextButton(
                onPressed: busy ? null : onRetry,
                child: Text(busy ? 'Loading…' : 'Try again',
                    semanticsLabel:
                        busy ? 'Loading your plan' : 'Try again, load your plan',
                    style: const TextStyle(
                        color: _link, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The compact plan chip for a settings-style row (Profile, Settings): the
/// plan's [ClientPlan.label] once known; "…" while the first read is in
/// flight; "—" when it failed, and then the chip itself is a busy-aware,
/// 44px, labelled Try again that re-reads the plan. [chip] draws the text in
/// the host screen's own style.
class PlanChipState extends ConsumerWidget {
  const PlanChipState({super.key, required this.chip});

  final Widget Function(String text) chip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(clientPlanProvider);
    final plan = knownPlan(planAsync);
    if (plan != null) return chip(plan.label.toUpperCase());
    if (!planAsync.hasError) {
      return Semantics(
          label: 'Loading your plan',
          child: ExcludeSemantics(child: chip('…')));
    }
    final busy = planAsync.isLoading;
    return Semantics(
      container: true,
      liveRegion: true,
      button: true,
      enabled: !busy,
      label: busy
          ? 'Loading your plan'
          : '${planLoadFailedMessage(planAsync.error!)} Try again',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          // While busy the tap is swallowed (not passed to the row, which
          // would navigate away mid-read) and does nothing: no second read.
          onTap: busy ? () {} : () => ref.invalidate(clientPlanProvider),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              chip('—'),
              const SizedBox(width: 6),
              busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _muted))
                  : const Icon(Icons.refresh_rounded, size: 16, color: _muted),
            ]),
          ),
        ),
      ),
    );
  }
}
