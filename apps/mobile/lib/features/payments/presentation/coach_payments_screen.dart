import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_background.dart';
import '../domain/payment_provider.dart';

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
    final statusAsync = ref.watch(coachConnectStatusProvider);
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          iconTheme: const IconThemeData(color: _white),
          title: const Text('Payments', style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        ),
        body: statusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
          error: (e, _) => Center(child: Text('Could not load.',
              textAlign: TextAlign.center, style: const TextStyle(color: _muted))),
          data: (s) {
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
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand, foregroundColor: _white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(ready ? 'Manage Stripe account' : connected ? 'Finish Stripe setup' : 'Connect Stripe',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    onPressed: () async {
                      final ok = await ref.read(paymentServiceProvider).connectStripeOnboard();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Could not open Stripe onboarding. Try again.'),
                          backgroundColor: Color(0xFFFFB4AB)));
                      }
                    },
                  )),
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
    final m = ref.watch(coachRevenueProvider).valueOrNull ?? const <String, double>{};
    final bal = ref.watch(coachBalanceProvider).valueOrNull ?? const <String, dynamic>{};
    String d(num? v) => '\$${(v ?? 0).toStringAsFixed(0)}';
    final pending = ((bal['pending'] as num?)?.toDouble() ?? 0) / 100.0;
    final completed = ((bal['paid'] as num?)?.toDouble() ?? 0) / 100.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('REVENUE', style: TextStyle(color: _muted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),
      Row(children: [
        _metric('This month', d(m['monthly']), _mint),
        const SizedBox(width: 10),
        _metric('Lifetime', d(m['lifetime']), _brand),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Pending payouts', d(pending), _amber),
        const SizedBox(width: 10),
        _metric('Completed payouts', d(completed), _mint),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Marketplace', d(m['marketplace']), _brand),
        const SizedBox(width: 10),
        _metric('Direct', d(m['direct']), _mint),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Active subscribers', '${(m['active_subscribers'] ?? 0).toInt()}', _amber),
        const SizedBox(width: 10),
        _metric('Active packages', '${(m['active_packages'] ?? 0).toInt()}', _brand),
      ]),
    ]);
  }

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
