import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/entitlements.dart';
import '../domain/payment_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/data/coach_relationship_service.dart';
import '../../../core/observability/app_failure.dart';

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

class ManageSubscriptionScreen extends ConsumerStatefulWidget {
  const ManageSubscriptionScreen({super.key});
  @override
  ConsumerState<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState
    extends ConsumerState<ManageSubscriptionScreen> {
  bool _portalLoading = false;

  static int _tierRank(String? kind) => kind == 'ai_guided' ? 2 : kind == 'self_guided' ? 1 : 0;

  /// Cancels the platform membership (all active membership rows) → Free.
  Future<void> _cancelPlan(
      BuildContext context, WidgetRef ref, List<Map<String, dynamic>> memberships) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
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
      ),
    );
    if (ok != true) return;
    final svc = ref.read(paymentServiceProvider);
    var allOk = true;
    for (final m in memberships) {
      final r = await svc.cancelSubscription(m['id'] as String);
      if (!r) allOk = false;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(allOk ? 'Switched to the Free plan.' : 'Could not cancel. Try again.')));
    ref.invalidate(clientPlanProvider);
    ref.invalidate(membershipTierProvider);
    ref.invalidate(mySubscriptionsProvider);
  }

  Future<void> _confirmStopCoach(
      BuildContext context, WidgetRef ref, Map<String, dynamic> rel) async {
    final messenger = ScaffoldMessenger.of(context);
    final coach = rel['coach'] as Map<String, dynamic>? ?? {};
    final coachName =
        '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Stop working with ${coachName.isEmpty ? 'this coach' : coachName}?',
            style: const TextStyle(color: _white, fontWeight: FontWeight.w800)),
        content: const Text(
          'Your coaching ends immediately and your coach will be notified. '
          'The remaining period is not reimbursed.',
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
      ),
    );
    if (ok != true) return;

    final coachId = rel['coach_id'] as String;
    // If there's a paid coach subscription, cancel it (also ends relationship +
    // notifies via the function); otherwise end the relationship directly.
    final subs = ref.read(mySubscriptionsProvider).valueOrNull ?? [];
    final coachSub = subs.firstWhere(
      (s) => s['kind'] == 'coach' &&
          s['coach_id'] == coachId &&
          ['active', 'trialing', 'past_due'].contains(s['status']),
      orElse: () => <String, dynamic>{},
    );
    // The message follows what happened, as `_cancelPlan`'s does: a failed
    // cancellation left the client billed and was announced as ended.
    bool ended;
    if (coachSub.isNotEmpty) {
      ended = await ref.read(paymentServiceProvider).cancelSubscription(coachSub['id'] as String);
    } else {
      try {
        await CoachRelationshipService().cancelCoach(coachId, 'client_cancelled', null);
        ended = true;
      } catch (e) {
        reportError('ManageSubscriptionScreen.stopCoach', e);
        ended = false;
      }
    }
    messenger.showSnackBar(SnackBar(content: Text(ended
        ? 'Coaching ended. Your coach has been notified.'
        : 'Could not cancel. Try again.')));
    ref.invalidate(myCoachesProvider);
    ref.invalidate(mySubscriptionsProvider);
    ref.invalidate(clientPlanProvider);
  }

  Future<void> _openPortal() async {
    setState(() => _portalLoading = true);
    final ok = await ref.read(paymentServiceProvider).openBillingPortal();
    if (!mounted) return;
    setState(() => _portalLoading = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No billing account yet. Subscribe to a plan first.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(clientPlanProvider);
    final subsAsync = ref.watch(mySubscriptionsProvider);
    final plan = planAsync.valueOrNull ?? ClientPlan.free;

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
                      Text(plan.label,
                          style: const TextStyle(
                              color: _white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Your plan — ONLY the platform membership (coaches show below).
            subsAsync.when(
              loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(color: _brand))),
              error: (_, __) => const SizedBox.shrink(),
              data: (subs) {
                final memberships = subs
                    .where((s) => ['self_guided', 'ai_guided'].contains(s['kind']) &&
                        ['active', 'trialing', 'past_due'].contains(s['status']))
                    .toList();
                if (memberships.isEmpty) {
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
                  onCancel: () => _cancelPlan(context, ref, memberships),
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
            ref.watch(myCoachesProvider).when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
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
                                    onStop: () => _confirmStopCoach(context, ref, c),
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
              label: _portalLoading ? 'Opening…' : 'Manage billing & payment method',
              onTap: _portalLoading ? null : _openPortal,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubRow extends StatelessWidget {
  final Map<String, dynamic> sub;
  final VoidCallback onCancel;
  const _SubRow({required this.sub, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final renews = DateTime.tryParse(sub['current_period_end'] as String? ?? '');
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
                      cancel
                          ? 'Cancels at period end'
                          : renews != null
                              ? 'Renews ${renews.month}/${renews.day}/${renews.year}'
                              : 'Active',
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
