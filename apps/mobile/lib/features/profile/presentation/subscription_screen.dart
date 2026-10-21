import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../payments/domain/entitlements.dart';

const _bg   = Color(0xFF0E0E0F);
const _pri  = Color(0xFFDDB7FF);
const _priC = Color(0xFFB76DFF);
const _tert = Color(0xFF6FFBBE);
const _gold = Color(0xFFFFD700);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  static const _tiers = [
    _TierInfo(
      id:    'basic',
      label: 'Basic',
      price: 'Free',
      color: Color(0xFF968E99),
      icon:  Icons.person_outline,
      perks: [
        'Workout tracking & history',
        'Basic nutrition logging',
        'Community access',
        'Progress photos',
      ],
    ),
    _TierInfo(
      id:    'pro',
      label: 'Pro',
      price: '\$19.99 / mo',
      color: Color(0xFFDDB7FF),
      icon:  Icons.auto_awesome_outlined,
      badge: 'POPULAR',
      perks: [
        'Everything in Basic',
        'AI-powered workout plans',
        'Advanced nutrition & macros',
        'Habit tracking system',
        'AI coach insights',
        'Unlimited check-ins',
      ],
    ),
    _TierInfo(
      id:    'elite',
      label: 'Elite',
      price: '\$49.99 / mo',
      color: Color(0xFFFFD700),
      icon:  Icons.workspace_premium_outlined,
      perks: [
        'Everything in Pro',
        'Dedicated human coach',
        'Weekly coach video calls',
        'Custom programming',
        'Priority support',
        'Transformation guarantee',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Track the client's effective plan (server-resolved from coaching_mode),
    // not the legacy membership_tier column (which always read "basic"). This
    // is the same source the Settings/Profile plan labels use, so the screen
    // stays consistent — and reactive — when the coaching mode changes.
    final plan = ref.watch(clientPlanProvider).valueOrNull ?? ClientPlan.free;
    final currentTier = switch (plan) {
      ClientPlan.coachGuided => 'elite',
      ClientPlan.aiGuided    => 'pro',
      _                      => 'basic', // free + self-guided map to Basic
    };
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          padding: EdgeInsets.only(left: 8, right: 20, top: top),
          decoration: const BoxDecoration(
            color: Color(0x99201F20),
            border: Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
          child: SizedBox(height: 56, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _pri, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop()),
            const Expanded(child: Center(child: Text('SUBSCRIPTION',
              style: TextStyle(color: _pri, fontSize: 16,
                fontWeight: FontWeight.w800, letterSpacing: 2)))),
            const SizedBox(width: 40),
          ])),
        ),

        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
          child: Column(children: [

            // Current plan hero
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D1B4E), Color(0xFF1A0D2E)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: _priC.withValues(alpha: 0.3))),
              child: Column(children: [
                const Icon(Icons.workspace_premium, color: _gold, size: 40),
                const SizedBox(height: 12),
                Text('Current Plan',
                  style: TextStyle(color: _pri.withValues(alpha: 0.7), fontSize: 12,
                    fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(_tierLabel(currentTier),
                  style: const TextStyle(color: _onS, fontSize: 28,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                  child: Text('Manage on App Store / Play Store',
                    style: TextStyle(color: _onSV, fontSize: 13))),
              ])),
            const SizedBox(height: 32),

            // Plan comparison
            const Align(alignment: Alignment.centerLeft,
              child: Padding(padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('AVAILABLE PLANS',
                  style: TextStyle(color: _onSV, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 2)))),

            ..._tiers.map((tier) => _TierCard(
              tier:       tier,
              isCurrent:  tier.id == currentTier,
            )),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _priC.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _priC.withValues(alpha: 0.18))),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _priC, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Upgrades and billing are managed through the App Store or Google Play Store.',
                  style: TextStyle(color: _onSV, fontSize: 12, height: 1.5))),
              ])),
          ]),
        )),
      ]),
    );
  }

  String _tierLabel(String tier) => switch (tier) {
    'pro'   => 'Pro',
    'elite' => 'Elite',
    _       => 'Basic',
  };
}

class _TierCard extends StatelessWidget {
  final _TierInfo tier;
  final bool isCurrent;
  const _TierCard({required this.tier, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCurrent
          ? tier.color.withValues(alpha: 0.08)
          : const Color(0x99201F20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent ? tier.color : const Color(0x0DFFFFFF),
          width: isCurrent ? 1.5 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: tier.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(tier.icon, color: tier.color, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(tier.label, style: TextStyle(
                color: tier.color, fontSize: 18, fontWeight: FontWeight.w800)),
              if (tier.badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(tier.badge!,
                    style: TextStyle(color: tier.color, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 1))),
              ],
            ]),
            Text(tier.price, style: const TextStyle(
              color: _out, fontSize: 13)),
          ])),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _tert.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _tert.withValues(alpha: 0.3))),
              child: const Text('CURRENT',
                style: TextStyle(color: _tert, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1))),
        ]),
        const SizedBox(height: 16),
        ...tier.perks.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.check_circle_outline, color: tier.color, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(p,
              style: const TextStyle(color: _onSV, fontSize: 13, height: 1.3))),
          ]))),
      ]));
  }
}

class _TierInfo {
  final String id, label, price;
  final Color color;
  final IconData icon;
  final List<String> perks;
  final String? badge;
  const _TierInfo({
    required this.id, required this.label, required this.price,
    required this.color, required this.icon, required this.perks,
    this.badge,
  });
}
