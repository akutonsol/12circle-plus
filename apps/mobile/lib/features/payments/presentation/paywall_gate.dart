import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/entitlements.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../../auth/domain/auth_provider.dart';

const _bg    = Color(0xFF030303);
const _brand = Color(0xFFA855F7);
const _white = Colors.white;
const _muted = Color(0xFFCFC2D6);

/// Wraps a screen that requires at least [required]. Free/under-tier users see
/// an upgrade prompt instead of the gated content. Used at the router level so
/// the gated screens themselves stay plan-agnostic.
class PaywallGate extends ConsumerWidget {
  final ClientPlan required;
  final String featureName;
  final Widget child;
  const PaywallGate({
    super.key,
    required this.required,
    required this.featureName,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Coaches always have access to coaching tools (their plan is a coach plan,
    // not a client plan) — never paywall them.
    final isCoach = ref.watch(currentUserProfileProvider).valueOrNull?['role'] == 'coach';
    if (isCoach) return child;
    final planAsync = ref.watch(clientPlanProvider);
    // Once we know the plan, keep rendering from it even while the provider is
    // refreshing (e.g. after a coaching-mode change re-resolves the plan). Only
    // the genuine first load (no value yet) shows the blocking spinner — a
    // mid-session refresh must never trap the user on a loading screen.
    final plan = planAsync.valueOrNull;
    if (plan != null) {
      return plan.atLeast(required) ? child : PaywallLocked(required: required, feature: featureName);
    }
    return planAsync.when(
      loading: () => const Scaffold(
          backgroundColor: _bg,
          body: Center(child: CircularProgressIndicator(color: _brand))),
      error: (_, __) => child, // fail open rather than lock a paying user out
      data: (plan) =>
          plan.atLeast(required) ? child : PaywallLocked(required: required, feature: featureName),
    );
  }
}

/// FIT-021 · the entitlement gate.
///
/// Public so its three declared controls can be asserted: `PaywallGate` reads
/// two Supabase-backed providers, and this state takes plain values.
class PaywallLocked extends StatelessWidget {
  final ClientPlan required;
  final String feature;
  const PaywallLocked({super.key, required this.required, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        // FIT-021 declares "Back". `AppBar`'s automatic leading is named by
        // Material's default tooltip, not by the package.
        leading: NamedIconButton(
          label: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back, color: _white, size: 20),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_brand, Color(0xFF6D28D9)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: _brand.withValues(alpha: 0.4), blurRadius: 20),
                  ],
                ),
                child: const Icon(Icons.lock_rounded, color: _white, size: 34),
              ),
              const SizedBox(height: 20),
              Text('$feature is a ${required.label} feature',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                  'Upgrade your plan to unlock this and more.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 14, height: 1.4)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: _white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => context.push('/upgrade'),
                  // FIT-021's wording, which differs from the shipped
                  // "See Plans" only in case — the locked screen wins.
                  child: const Text('See plans',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 4),
              // FIT-021 declares a second action, and it did not exist. A user
              // who hits a paywall could previously only leave by the system
              // back gesture — there was nothing on screen that said they were
              // allowed to.
              Semantics(
                button: true,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    child: const Text('Not now',
                        style: TextStyle(
                            color: _muted, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
