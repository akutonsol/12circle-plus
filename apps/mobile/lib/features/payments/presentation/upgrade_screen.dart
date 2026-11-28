import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/payment_service.dart' show CancelOutcome, CancelSubscriptionOutcome, ownerGone, signedInUid, whenOwnerGone;
import '../domain/entitlements.dart';
import '../domain/payment_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/presentation/coach_packages_view_sheet.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
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
    final account = ref.watch(paymentAccountProvider);
    final read = ref.watch(ownedClientPlanProvider);
    reportPlanReadFailure(ref, 'UpgradeScreen.clientPlan');
    // P0-FL-17: an unread plan is not Free. Until client_plan() has answered,
    // no card is "Current" and nothing can be bought or switched — a coached
    // client was offered the plan they already had as if it were new.
    // P0-FL-60a: nor is another account's plan this one's (A-21).
    final current = read.hasValue ? read.value : null;

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
              if (read.error != null)
                PlanLoadFailedNotice(
                  error: read.error!,
                  busy: read.isLoading,
                  detail: "Plans can't be changed until it loads.",
                  onRetry: () => ref.invalidate(clientPlanProvider),
                )
              else
                const PlanLoadingRow(),
              const SizedBox(height: 16),
            ] else if (read.error != null) ...[
              // P0-FL-60a: a failed refresh keeps the plan, and says so.
              PlanLoadFailedNotice(
                error: read.error!,
                busy: read.isLoading,
                detail: kPlanFromLastTime,
                onRetry: () => ref.invalidate(clientPlanProvider),
              ),
              const SizedBox(height: 16),
            ],
            // Keyed by account: a card's spinner is the action of the account
            // that tapped it (P0-FL-60a).
            ..._plans.map((p) => _PlanCard(
                  key: ValueKey((account, p.plan)),
                  account: account,
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
  /// The account this card was built for (P0-FL-60a).
  final String? account;
  final _Plan plan;
  final bool isCurrent;
  /// Null while the plan is unknown: every action is disabled.
  final ClientPlan? current;
  const _PlanCard(
      {super.key,
      required this.account,
      required this.plan,
      required this.isCurrent,
      required this.current});
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
    try {
      await _act();
    } finally {
      // Whatever ended it — also the account leaving, after which the same
      // card is A's again once A is back (A → B → A): not stuck on its spinner.
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _act() async {
    final p = widget.plan;
    // P0-FL-60a (W26): every step below is this account's. When it is gone
    // nothing more is sent, opened or said — it is not the next one's action.
    // The owner is who the card was drawn for, not who is signed in at the tap.
    final owner = widget.account;
    bool gone(String what) => ownerGone(owner, 'UpgradeScreen', what);
    // After something was sent: [owner] never sees its outcome (P0-FL-63b).
    bool outcomeGone(String origin, String flow) =>
        outcomeOwnerGone(owner, origin, flow);
    const freeOrigin = 'UpgradeScreen.switchToFree';
    const changeOrigin = 'UpgradeScreen.planChange';
    if (gone('plan card')) return;
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
      //
      // Bounded by [owner] (P0-FL-63b): an account change discards the read
      // in flight, and with nothing else watching the subscriptions no next
      // answer ever comes — the tap never ended and nothing was recorded. It
      // now ends when [owner] leaves: nothing sent, nothing said, recorded once.
      final left = Completer<void>();
      final stopWatching = whenOwnerGone(owner, left.complete);
      final read = ref.read(mySubscriptionsProvider.future);
      final List<Map<String, dynamic>>? subs;
      try {
        subs = await Future.any([
          read,
          left.future.then((_) => null),
        ]);
      } catch (e, st) {
        // P0-FL-60a: the cause was lost, and nothing said that it was the
        // read that failed and that nothing had been cancelled.
        reportError('UpgradeScreen.mySubscriptions', e, st);
        showOwnedSnackBar(messenger, owner, SnackBar(
            content: Text('${couldntMessage('load your subscriptions', e)} '
                'Nothing was cancelled.')),
            origin: freeOrigin, flow: 'switch to Free');
        return;
      } finally {
        stopWatching();
      }
      if (subs == null) {
        recordOutcomeNotShown(freeOrigin, 'switch to Free');
        // A failure of the read that lands after is still recorded, as the
        // catch above records it; nothing of it is said.
        unawaited(read.then<void>((_) {}, onError: (Object e, StackTrace st) =>
            reportError('UpgradeScreen.mySubscriptions', e, st)));
        return;
      }
      if (gone('switch to Free')) return;
      if (!mounted) return;
      final memberships = subs
          .where((s) => ['self_guided', 'ai_guided'].contains(s['kind']) &&
              ['active', 'trialing', 'past_due'].contains(s['status']))
          .toList();
      if (memberships.isEmpty) return;
      final confirmed = await _confirmDowngradeToFree();
      if (gone('switch to Free') || confirmed != true) return;
      if (mounted) setState(() => _loading = true);
      // The message follows what happened, as /manage-subscription's does: a
      // failed cancellation left the client billed and was announced as Free.
      final outcomes = <CancelOutcome>{};
      for (final m in memberships) {
        if (outcomes.isEmpty
            ? gone('switch to Free')
            : outcomeGone(freeOrigin, 'switch to Free')) {
          return;
        }
        outcomes.add(
            await paymentSvc.cancelSubscriptionOutcome(m['id'] as String));
      }
      if (outcomeGone(freeOrigin, 'switch to Free')) return;
      _refresh();
      showOwnedSnackBar(messenger, owner,
          SnackBar(content: Text(switchToFreeMessage(outcomes))),
          origin: freeOrigin, flow: 'switch to Free');
      return;
    }

    // Paid membership target. Always ask the server to change an existing
    // membership in place first -- whatever plan this screen shows: a member
    // who also has a coach shows as Coach-Guided while a membership still bills,
    // and skipping this sent them to buy a SECOND membership.
    if (mounted) setState(() => _loading = true);
    final result = await paymentSvc.changeMembership(p.kind!);
    // needs_checkout changed nothing and says nothing: only the checkout that
    // would follow is stopped. Any other answer is an outcome to say.
    if (result == 'needs_checkout'
        ? gone('plan change')
        : outcomeGone(changeOrigin, 'plan change')) {
      return;
    }
    if (result == 'changed') {
      _refresh();
      showOwnedSnackBar(messenger, owner,
          SnackBar(content: Text('Your plan is now ${p.name}.')),
          origin: changeOrigin, flow: 'plan change');
      return;
    }
    // Only an explicit "there is no membership to change" may lead to a new
    // checkout. An error used to fall through to one too -- including when the
    // swap had gone through at Stripe and only the reply was lost: two
    // memberships, both billed.
    if (result != 'needs_checkout') {
      showOwnedSnackBar(messenger, owner, SnackBar(content: Text(switch (result) {
        'payment_issue' =>
          'Your current membership has a payment problem. Update your '
              'payment method in Billing, then change your plan.',
        // Not known to have failed: never "try again" before looking.
        'unconfirmed' => "Couldn't confirm your plan change — check your plan "
            'before trying again.',
        _ => "Couldn't change your plan. Try again.",
      })), origin: changeOrigin, flow: 'plan change');
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
    await launchCheckout(context, ref, kind: p.kind!, owner: owner);
    if (!mounted) return; // embedded checkout navigated away; success screen refreshes
    if (signedInUid() != owner) return;
    _refresh();
  }

  Future<bool?> _confirmDowngradeToFree() => showDialog<bool>(
        context: context,
        builder: (dctx) => OwnedDialog(
            owner: widget.account,
            child: AlertDialog(
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
        )),
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
              // P0-FL-60a (A-21): this account's coach only, and a failed
              // read is said — it looked like having no coach.
              final coachRead = ref.watch(_ownedAssignedCoachProvider);
              if (!coachRead.hasValue && coachRead.error != null) {
                return SectionLoadFailure(
                  what: 'your coach',
                  error: coachRead.error,
                  busy: coachRead.isLoading,
                  onRetry: () => ref.invalidate(assignedCoachProvider),
                );
              }
              final coach = coachRead.value;
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
                  onPressed: () {
                    // This account's coach, to this account only.
                    if (ownerGone(widget.account, 'UpgradeScreen',
                        "the coach's packages")) {
                      return;
                    }
                    openOwnedRoute(
                        context,
                        widget.account,
                        () => showCoachPackagesSheet(
                            context, coach['id'] as String, coachName));
                  },
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

/// client_plan()'s answer for the account signed in now — never one held from
/// another (P0-FL-60a). `clientPlanProvider` is what to invalidate.
final ownedClientPlanProvider = ownedReadProvider(clientPlanProvider);

final _ownedAssignedCoachProvider = ownedReadProvider(assignedCoachProvider,
    origin: 'UpgradeScreen.assignedCoach');

/// Said with a failed refresh whose plan is still shown.
const kPlanFromLastTime = 'This is the plan from the last time it loaded.';

/// What switching to Free came to. The message follows what happened.
String switchToFreeMessage(Set<CancelOutcome> outcomes) =>
    outcomes.contains(CancelOutcome.unconfirmed)
        ? "Couldn't confirm the cancellation — check your plan before trying "
            'again.'
        : outcomes.contains(CancelOutcome.refused)
            ? 'Could not cancel. Try again.'
            : 'Switched to the Free plan.';

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
    final read = ref.watch(ownedClientPlanProvider);
    final plan = read.value;
    if (plan != null) return chip(plan.label.toUpperCase());
    final error = read.error;
    if (error == null) {
      return Semantics(
          label: 'Loading your plan',
          child: ExcludeSemantics(child: chip('…')));
    }
    final busy = read.isLoading;
    // While busy the tap is swallowed (not passed to the row, which would
    // navigate away mid-read) and does nothing: no second read.
    final VoidCallback onTap =
        busy ? () {} : () => ref.invalidate(clientPlanProvider);
    return Semantics(
      container: true,
      liveRegion: true,
      button: true,
      enabled: !busy,
      label: busy
          ? 'Loading your plan'
          : '${planLoadFailedMessage(error)} Try again',
      // ExcludeSemantics drops the InkWell's tap action, so the node carries
      // it itself: TalkBack / VoiceOver users can retry too (UX-N1).
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
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
