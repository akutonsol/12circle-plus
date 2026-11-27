import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/payment_service.dart' show
    CancelOutcome, CancelSubscriptionOutcome, definitelyRefused, ownerGone;
import '../domain/entitlements.dart';
import '../domain/payment_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/data/coach_relationship_service.dart';
import '../../dashboard/domain/still_reading.dart' show boundTo, stillSignedIn;
import '../../../core/observability/app_failure.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import 'checkout_launcher.dart'
    show OwnedDialog, outcomeOwnerGone, recordOutcomeNotShown, showOwnedSnackBar;
import 'upgrade_screen.dart'
    show PlanLoadFailedNotice, kPlanFromLastTime, ownedClientPlanProvider,
        reportPlanReadFailure, switchToFreeMessage;

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);

String _kindLabel(String? kind, String? tier) => switch (kind) {
      'self_guided' => 'Self-Guided Membership',
      'ai_guided' => 'AI-Guided Membership',
      'coach' => 'Coach Subscription',
      'coach_plan' => 'Coach Plan — ${tier ?? ''}'.trim(),
      _ => kind ?? 'Subscription',
    };

final _ownedMyCoachesProvider = ownedReadProvider(myCoachesProvider);

/// This account's list, its failure (kept, busy, through a retry), or loading —
/// never another account's of either (P0-FL-60a).
Widget _ownedWhen<T>(OwnedRead<T> read,
        {required Widget Function() loading,
        required Widget Function() error,
        required Widget Function(T value) data}) =>
    read.error != null
        ? error()
        : read.hasValue
            ? data(read.value as T)
            : loading();

class ManageSubscriptionScreen extends ConsumerStatefulWidget {
  const ManageSubscriptionScreen({super.key});
  @override
  ConsumerState<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState
    extends ConsumerState<ManageSubscriptionScreen> {
  /// Whose billing page is being opened, if anyone's: busy for them only.
  ({String? uid})? _portal;

  static int _tierRank(String? kind) => kind == 'ai_guided' ? 2 : kind == 'self_guided' ? 1 : 0;

  /// Cancels the platform membership (all active membership rows) → Free.
  Future<void> _cancelPlan(
      BuildContext context, WidgetRef ref, String? owner,
      List<Map<String, dynamic>> memberships) async {
    final messenger = ScaffoldMessenger.of(context);
    // P0-FL-60a: these are this account's rows; nothing is cancelled, and
    // nothing said, once it is gone. [owner] is who the row was drawn for.
    bool gone() =>
        ownerGone(owner, 'ManageSubscriptionScreen', 'switch to Free');
    if (gone()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => OwnedDialog(
          owner: owner,
          child: AlertDialog(
        backgroundColor: _card,
        title: const Text('Switch to Free?',
            style: TextStyle(color: _white, fontWeight: FontWeight.w800)),
        content: const Text(
          'Your plan drops to Free immediately. Access to paid features ends now and the '
          'remaining period is not reimbursed.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Keep plan', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Switch to Free',
                style: TextStyle(color: Color(0xFFFFB4AB), fontWeight: FontWeight.w700)),
          ),
        ],
      )),
    );
    if (gone() || ok != true || !mounted) return;
    final svc = ref.read(paymentServiceProvider);
    final outcomes = <CancelOutcome>{};
    // After the first cancellation was sent, a stop leaves its outcome
    // unseen by [owner] — recorded as such (P0-FL-63b).
    bool outcomeGone() => outcomeOwnerGone(
        owner, 'ManageSubscriptionScreen.switchToFree', 'switch to Free');
    for (final m in memberships) {
      if (outcomes.isEmpty ? gone() : outcomeGone()) return;
      outcomes.add(await svc.cancelSubscriptionOutcome(m['id'] as String));
    }
    if (outcomeGone()) return;
    showOwnedSnackBar(messenger, owner,
        SnackBar(content: Text(switchToFreeMessage(outcomes))),
        origin: 'ManageSubscriptionScreen.switchToFree', flow: 'switch to Free');
    if (!mounted) return;
    ref.invalidate(clientPlanProvider);
    ref.invalidate(membershipTierProvider);
    ref.invalidate(mySubscriptionsProvider);
  }

  Future<void> _confirmStopCoach(
      BuildContext context, WidgetRef ref, String? owner,
      Map<String, dynamic> rel) async {
    final messenger = ScaffoldMessenger.of(context);
    final coach = rel['coach'] as Map<String, dynamic>? ?? {};
    final coachName =
        '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
    // P0-FL-60a: cancelCoach without an account ends the coaching of WHOEVER
    // is signed in — with the same coach, the next account's. Only for the
    // account that was asked: [owner] is who the row was drawn for.
    bool gone() =>
        ownerGone(owner, 'ManageSubscriptionScreen', 'stop coaching');
    if (gone()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => OwnedDialog(
          owner: owner,
          child: AlertDialog(
        backgroundColor: _card,
        title: Text('Stop working with ${coachName.isEmpty ? 'this coach' : coachName}?',
            style: const TextStyle(color: _white, fontWeight: FontWeight.w800)),
        content: const Text(
          'If you pay for this coach, coaching continues until the end of the '
          'period you have paid for, then ends. Otherwise it ends now. Your '
          'coach will be notified.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Keep coach', style: TextStyle(color: _muted))),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Yes, stop',
                  style: TextStyle(color: Color(0xFFFFB4AB), fontWeight: FontWeight.w700))),
        ],
      )),
    );
    if (gone() || ok != true) return;

    final coachId = rel['coach_id'] as String;
    // One policy for every way of ending coaching (owner decision 2): a paid
    // coaching subscription -- coach OR monthly package; this used to look for
    // 'coach' only and so left package subscriptions billing -- is cancelled at
    // the end of the paid period and coaching lasts until then; without one the
    // relationship ends now. The message follows what actually happened.
    const outcomeOrigin = 'ManageSubscriptionScreen.stopCoach';
    String message;
    try {
      // P0-FL-62b: every step for [owner] (an owner nobody knows is nobody),
      // never for whoever is signed in when a step runs.
      final end = await CoachRelationshipService().cancelCoach(
          coachId, 'client_cancelled', null,
          expectedUid: boundTo(owner));
      message = end.describe();
    } on AccountChangedError {
      // Recorded by the service; nothing of it is for whoever is signed in
      // now. (Back as the same member: what is left is read again.) What
      // was done before the stop is not known to [owner] (P0-FL-63b).
      recordOutcomeNotShown(outcomeOrigin, 'stop coaching');
      if (stillSignedIn(owner) && mounted) {
        ref.invalidate(myCoachesProvider);
        ref.invalidate(mySubscriptionsProvider);
        ref.invalidate(clientPlanProvider);
      }
      return;
    } catch (e, st) {
      reportError('ManageSubscriptionScreen.stopCoach', e, st);
      // cancelCoach's StateError says what happened ("No active coaching with
      // this coach", "You are signed out"); say it, as the marketplace does.
      message = e is StateError
          ? e.message
          : definitelyRefused(e)
              ? 'Could not end coaching. Nothing was changed. Try again.'
              // Not known to have failed: the reply may be all that was lost.
              : "Couldn't confirm that coaching ended — check your coaches "
                  'before trying again.';
    }
    if (outcomeOwnerGone(owner, outcomeOrigin, 'stop coaching')) return;
    showOwnedSnackBar(messenger, owner, SnackBar(content: Text(message)),
        origin: outcomeOrigin, flow: 'stop coaching');
    if (!mounted) return;
    ref.invalidate(myCoachesProvider);
    ref.invalidate(mySubscriptionsProvider);
    ref.invalidate(clientPlanProvider);
  }

  Future<void> _openPortal(String? owner) async {
    // [owner] is who the button was drawn for.
    if (ownerGone(owner, 'ManageSubscriptionScreen', 'open billing')) return;
    setState(() => _portal = (uid: owner));
    String? problem;
    try {
      if (!await ref.read(paymentServiceProvider).openBillingPortal()) {
        problem = 'No billing account yet. Subscribe to a plan first.';
      }
    } catch (e) {
      // Recorded by the service. P0-FL-60a: a failure is not "no account".
      problem = couldntMessage('open billing', e);
    }
    if (!mounted) {
      // The screen went with the account (an account scope) (P0-FL-63b).
      if (problem != null) {
        outcomeOwnerGone(owner, 'ManageSubscriptionScreen.openBilling',
            'open billing');
      }
      return;
    }
    // Another account's own request is still running: not ours to end.
    if (_portal?.uid == owner) setState(() => _portal = null);
    if (problem != null) {
      showOwnedSnackBar(ScaffoldMessenger.of(context), owner,
          SnackBar(content: Text(problem)),
          origin: 'ManageSubscriptionScreen.openBilling', flow: 'open billing');
    }
  }

  /// Records a failure of [provider] once, when it settles.
  void _reportSettledFailure(
      ProviderListenable<AsyncValue<List<Map<String, dynamic>>>> provider,
      String origin) {
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(provider,
        (previous, next) {
      final settled = next.hasError &&
          !next.isLoading &&
          (previous == null || previous.isLoading || !previous.hasError);
      if (settled) reportError(origin, next.error!, next.stackTrace);
    });
  }

  Widget _subsFailure(OwnedRead<List<Map<String, dynamic>>> subsAsync) =>
      SectionLoadFailure(
        what: 'your subscriptions',
        error: subsAsync.error,
        busy: subsAsync.isLoading,
        accent: _brand,
        textColor: _white,
        mutedColor: _muted,
        onRetry: () => ref.invalidate(mySubscriptionsProvider),
      );

  Widget _coachesFailure(OwnedRead<List<Map<String, dynamic>>> coachesAsync) =>
      SectionLoadFailure(
        what: 'your coaches',
        error: coachesAsync.error,
        busy: coachesAsync.isLoading,
        accent: _brand,
        textColor: _white,
        mutedColor: _muted,
        onRetry: () => ref.invalidate(myCoachesProvider),
      );

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(paymentAccountProvider);
    final planRead = ref.watch(ownedClientPlanProvider);
    final portal = _portal;
    final portalLoading = portal != null && portal.uid == account;
    final subsAsync = ref.watch(ownedMySubscriptionsProvider);
    final coachesAsync = ref.watch(_ownedMyCoachesProvider);
    // P0-FL-40: these reads propagate their failures; record each once, when
    // it settles (not again on every rebuild).
    _reportSettledFailure(mySubscriptionsProvider,
        'ManageSubscriptionScreen.mySubscriptions');
    _reportSettledFailure(myCoachesProvider,
        'ManageSubscriptionScreen.myCoaches');
    // P0-FL-17: an unread plan is not Free — "…" while loading, "—" and a
    // failure notice with Try again when the read failed.
    reportPlanReadFailure(ref, 'ManageSubscriptionScreen.clientPlan');
    // P0-FL-60a (A-21): this account's plan only.
    final plan = planRead.value;
    final planError = planRead.error;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: const Text('Subscription',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: _brand,
        backgroundColor: _card,
        onRefresh: () async {
          ref.invalidate(clientPlanProvider);
          ref.invalidate(mySubscriptionsProvider);
          // UX-4: the coaches section is on this page too — a pull re-reads it
          // (including after a failed read), not just the subscriptions.
          ref.invalidate(myCoachesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Current plan banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A1A4E), _card],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded, color: _mint, size: 30),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current plan',
                          style: TextStyle(color: _muted, fontSize: 12)),
                      Semantics(
                        label: plan != null
                            ? null
                            : planError != null
                                ? "Your plan couldn't be loaded"
                                : 'Loading your plan',
                        child: ExcludeSemantics(
                          excluding: plan == null,
                          child: Text(
                              plan?.label ?? (planError != null ? '—' : '…'),
                              style: const TextStyle(
                                  color: _white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (planError != null) ...[
              const SizedBox(height: 12),
              PlanLoadFailedNotice(
                error: planError,
                busy: planRead.isLoading,
                detail: plan == null ? null : kPlanFromLastTime,
                onRetry: () => ref.invalidate(clientPlanProvider),
              ),
            ],
            const SizedBox(height: 16),

            // Your plan — ONLY the platform membership (coaches show below).
            _ownedWhen(
              subsAsync,
              // P0-FL-40: a retry of a failed read takes this arm — keep the
              // failure card (busy), not a spinner that hides what happened.
              loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(
                          color: _brand,
                          semanticsLabel: 'Loading your subscriptions'))),
              // P0-FL-40: a failed read rendered nothing — exactly what a
              // member with no membership sees. Say it failed.
              error: () => _subsFailure(subsAsync),
              data: (subs) {
                final memberships = subs
                    .where((s) => ['self_guided', 'ai_guided'].contains(s['kind']) &&
                        ['active', 'trialing', 'past_due'].contains(s['status']))
                    .toList();
                if (memberships.isEmpty) {
                  // No membership is not "Free plan" while the plan itself
                  // is unknown (P0-FL-17): the banner says what is known.
                  if (plan == null) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        'You’re on the Free plan. Upgrade any time to unlock more.',
                        style: TextStyle(color: _muted)),
                  );
                }
                // Collapse any duplicates to the highest tier (one plan shown).
                memberships.sort((a, b) =>
                    _tierRank(b['kind'] as String?) - _tierRank(a['kind'] as String?));
                return _SubRow(
                  sub: memberships.first,
                  onCancel: () => _cancelPlan(context, ref, account, memberships),
                );
              },
            ),
            const SizedBox(height: 24),

            // Your coaches (multi-coach)
            Row(
              children: [
                const Text('Your Coaches',
                    style: TextStyle(
                        color: _white, fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.push('/coach-marketplace'),
                  icon: const Icon(Icons.add, size: 16, color: _brand),
                  label: const Text('Find a coach',
                      style: TextStyle(color: _brand, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ownedWhen(
                  coachesAsync,
                  // P0-FL-40: loading was blank and a failure was blank — the
                  // member saw "no coaches" either way. Loading is a neutral
                  // placeholder; a failure says so, with Try again (kept,
                  // busy, while the retry is in flight).
                  loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: _brand, strokeWidth: 2,
                                semanticsLabel: 'Loading your coaches')))),
                  error: () => _coachesFailure(coachesAsync),
                  data: (coaches) => coaches.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                              'You’re not working with a coach yet. Add a fitness or nutrition coach any time.',
                              style: TextStyle(color: _muted, fontSize: 13)),
                        )
                      : Column(
                          children: coaches
                              .map((c) => _CoachRow(
                                    rel: c,
                                    onStop: () => _confirmStopCoach(context, ref, account, c),
                                  ))
                              .toList(),
                        ),
                ),
            const SizedBox(height: 20),

            // Actions
            _ActionButton(
              icon: Icons.upgrade_rounded,
              label: 'Change plan',
              onTap: () => context.push('/upgrade'),
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.credit_card_rounded,
              label: portalLoading ? 'Opening…' : 'Manage billing & payment method',
              onTap: portalLoading ? null : () => _openPortal(account),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Renews m/d/yyyy" on the member's own day. `current_period_end` is a UTC
/// instant and was printed as parsed — the UTC date, a day late for a US
/// evening renewal.
@visibleForTesting
String renewsLabel(String? periodEnd) {
  final d = DateTime.tryParse(periodEnd ?? '')?.toLocal();
  return d == null ? 'Active' : 'Renews ${d.month}/${d.day}/${d.year}';
}

class _SubRow extends StatelessWidget {
  final Map<String, dynamic> sub;
  final VoidCallback onCancel;
  const _SubRow({required this.sub, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final cancel = sub['cancel_at_period_end'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kindLabel(sub['kind'] as String?, sub['plan_tier'] as String?),
                        style: const TextStyle(
                            color: _white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      cancel ? 'Cancels at period end' : renewsLabel(sub['current_period_end'] as String?),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (cancel ? _muted : _mint).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cancel ? 'Ending' : 'Active',
                    style: TextStyle(
                        color: cancel ? _muted : _mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFFFB4AB)),
              label: const Text('Cancel',
                  style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachRow extends StatelessWidget {
  final Map<String, dynamic> rel;
  final VoidCallback onStop;
  const _CoachRow({required this.rel, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final coach = rel['coach'] as Map<String, dynamic>? ?? {};
    final name = '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
    final specialty = (rel['specialty'] as String?) ?? 'general';
    final price = (rel['monthly_price'] as num?)?.toDouble() ??
        (coach['pricing_monthly'] as num?)?.toDouble();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _brand.withValues(alpha: 0.18),
            child: Text(initial,
                style: const TextStyle(color: _mint, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Coach' : name,
                    style: const TextStyle(
                        color: _white, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(
                    '${specialty[0].toUpperCase()}${specialty.substring(1)}'
                    '${price != null ? ' · \$${price.toStringAsFixed(0)}/mo' : ''}',
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Stop',
                style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, color: _brand, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: _muted),
          ],
        ),
      ),
    );
  }
}
