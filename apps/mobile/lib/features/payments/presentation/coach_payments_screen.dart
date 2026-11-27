import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_background.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../data/payment_service.dart' show ownerGone;
import '../domain/payment_provider.dart';
import 'checkout_launcher.dart' show outcomeOwnerGone, showOwnedSnackBar;

const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _white = Colors.white;
const _muted = Color(0xFFCFC2D6);
const _mint  = Color(0xFF6FFBBE);
const _amber = Color(0xFFFFD479);

/// Coach: connect a Stripe account so client coaching payments flow directly to
/// you. 12 Circle only takes a commission on marketplace-acquired clients.
class CoachPaymentsScreen extends ConsumerWidget {
  const CoachPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P0-FL-60a (A-19): this account's status only. A failed refresh keeps
    // what this account last read, and says so.
    final account = ref.watch(paymentAccountProvider);
    final status = ref.watch(ownedConnectStatusProvider);
    final s = status.value;
    final Widget? failure = status.error == null
        ? null
        : SectionLoadFailure(
            what: 'your Stripe status',
            error: status.error,
            busy: status.isLoading,
            accent: _brand,
            detail: s == null
                ? null
                : 'What’s below is from the last time it loaded.',
            onRetry: () => ref.invalidate(coachConnectStatusProvider),
          );
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          iconTheme: const IconThemeData(color: _white),
          title: const Text('Payments', style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        ),
        body: Builder(
          builder: (context) {
            if (s == null) {
              return failure == null
                  ? const Center(child: CircularProgressIndicator(color: _brand))
                  : Center(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16), child: failure));
            }
            final connected = s['connected'] == true;
            final chargesOn = s['charges_enabled'] == true;
            final payoutsOn = s['payouts_enabled'] == true;
            final ready = connected && chargesOn;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(coachConnectStatusProvider);
                ref.invalidate(coachRevenueProvider);
                ref.invalidate(coachBalanceProvider);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (failure != null) ...[
                    failure,
                    const SizedBox(height: 12),
                  ],
                  _RevenueSection(),
                  const SizedBox(height: 16),
                  // Status banner
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        (ready ? _mint : _amber).withValues(alpha: 0.18), _card]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: (ready ? _mint : _amber).withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      Icon(ready ? Icons.verified_rounded : Icons.account_balance_wallet_outlined,
                          color: ready ? _mint : _amber, size: 30),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ready ? 'Payments active' : connected ? 'Finish setup' : 'Not connected',
                            style: TextStyle(color: ready ? _mint : _amber, fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(ready
                            ? 'You can sell packages & plans — payments go straight to your Stripe account.'
                            : 'Connect Stripe to receive client payments directly.',
                            style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  _statusRow('Account connected', connected),
                  _statusRow('Accept charges', chargesOn),
                  _statusRow('Payouts enabled', payoutsOn),
                  const SizedBox(height: 20),
                  // How money flows
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _brd)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      Text('HOW PAYMENTS WORK', style: TextStyle(color: _muted, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                      SizedBox(height: 10),
                      _Bullet('Clients pay you directly through your connected Stripe account.'),
                      _Bullet('Clients you invited: you keep 100% (no platform commission).'),
                      _Bullet('Marketplace clients: 12 Circle takes a 10% commission.'),
                      _Bullet('Platform plan fees (Starter/Growth/Elite) are billed separately.'),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  // Keyed by account: its spinner is the action of the account
                  // that tapped it.
                  _StripeButton(
                    key: ValueKey(account),
                    account: account,
                    label: ready ? 'Manage Stripe account' : connected ? 'Finish Stripe setup' : 'Connect Stripe',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statusRow(String label, bool on) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: on ? _mint : _muted, size: 18),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: on ? _white : _muted, fontSize: 14)),
    ]),
  );
}

/// Opens the coach's Stripe pages. Busy while the link is made: a second tap
/// asked for a second link and could open two pages (P0-FL-60a).
class _StripeButton extends ConsumerStatefulWidget {
  const _StripeButton({super.key, required this.account, required this.label});

  /// The account this button was built for.
  final String? account;
  final String label;
  @override
  ConsumerState<_StripeButton> createState() => _StripeButtonState();
}

class _StripeButtonState extends ConsumerState<_StripeButton> {
  bool _busy = false;

  Future<void> _open() async {
    final owner = widget.account;
    if (ownerGone(owner, 'CoachPaymentsScreen', 'open Stripe')) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String? problem;
    try {
      await ref.read(paymentServiceProvider).connectStripeOnboard();
    } catch (e) {
      // Recorded by the service; said to the account that asked, nobody else.
      problem = couldntMessage('open Stripe', e);
    }
    const origin = 'CoachPaymentsScreen.openStripe';
    if (!mounted) {
      // The screen went with the account (an account scope) (P0-FL-63b).
      if (problem != null) outcomeOwnerGone(owner, origin, 'open Stripe');
      return;
    }
    setState(() => _busy = false);
    if (problem != null) {
      showOwnedSnackBar(messenger, owner, SnackBar(
          content: Text(problem), backgroundColor: const Color(0xFFFFB4AB)),
          origin: origin, flow: 'open Stripe');
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand, foregroundColor: _white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          icon: _busy
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _white, semanticsLabel: 'Opening Stripe'))
              : const Icon(Icons.link_rounded),
          label: Text(widget.label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          onPressed: _busy ? null : _open,
        ),
      );
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('•  ', style: TextStyle(color: _brand, fontSize: 13)),
      Expanded(child: Text(text, style: const TextStyle(color: _muted, fontSize: 13, height: 1.4))),
    ]),
  );
}

// Coach revenue analytics: monthly, lifetime, subscribers, pending payouts,
// and the marketplace vs direct split.
class _RevenueSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A figure that was not read shows a dash, never zero (EC-14): a failed or
    // pending read is not a zero balance. Nor is another coach's figure this
    // one's (P0-FL-60a, A-19); a failed refresh keeps this coach's, and says so.
    final revenue = ref.watch(ownedRevenueProvider);
    final balance = ref.watch(ownedBalanceProvider);
    final m = revenue.value;
    final bal = balance.value;
    String d(num? v) => v == null ? '—' : '\$${v.toStringAsFixed(0)}';
    final pending = bal == null ? null : ((bal['pending'] as num?)?.toDouble() ?? 0) / 100.0;
    final completed = bal == null ? null : ((bal['paid'] as num?)?.toDouble() ?? 0) / 100.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('REVENUE', style: TextStyle(color: _muted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
      if (revenue.error != null)
        _failed('your revenue', revenue,
            () => ref.invalidate(coachRevenueProvider)),
      if (balance.error != null)
        _failed('your payouts', balance,
            () => ref.invalidate(coachBalanceProvider)),
      const SizedBox(height: 10),
      Row(children: [
        _metric('This month', d(m?['monthly']), _mint),
        const SizedBox(width: 10),
        _metric('Lifetime', d(m?['lifetime']), _brand),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Pending payouts', d(pending), _amber),
        const SizedBox(width: 10),
        _metric('Completed payouts', d(completed), _mint),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Marketplace', d(m?['marketplace']), _brand),
        const SizedBox(width: 10),
        _metric('Direct', d(m?['direct']), _mint),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Active subscribers', m == null ? '—' : '${(m['active_subscribers'] ?? 0).toInt()}', _amber),
        const SizedBox(width: 10),
        _metric('Active packages', m == null ? '—' : '${(m['active_packages'] ?? 0).toInt()}', _brand),
      ]),
    ]);
  }

  Widget _failed(String what, OwnedRead<Object?> read, VoidCallback onRetry) =>
      SectionLoadFailure(
        what: what,
        error: read.error,
        busy: read.isLoading,
        accent: _brand,
        detail: read.hasValue
            ? 'These figures are from the last time they loaded.'
            : null,
        onRetry: onRetry,
      );

  Widget _metric(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _brd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
    ),
  );
}
