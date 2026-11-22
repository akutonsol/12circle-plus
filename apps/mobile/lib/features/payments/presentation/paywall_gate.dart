import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/entitlements.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../../auth/domain/auth_provider.dart';
import '../../profile/presentation/widgets/profile_load_failed_notice.dart';

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
    //
    // P0-FL-44 · only a SUCCESSFUL profile read decides that. The role used to
    // be `valueOrNull?['role']`, which is null both while the profile loads
    // and when its read FAILED (P0-FL-16 made the provider rethrow) — so a
    // coach fell through to the client plan check and could be shown
    // PaywallLocked, "upgrade your plan": a false fact about their account.
    // Unknown is now neither locked nor opened. A refresh that fails after a
    // successful read keeps that read's role (Riverpod keeps the previous
    // value), so `hasValue` — not `hasError` — is the test.
    final profileAsync = ref.watch(currentUserProfileProvider);
    if (!profileAsync.hasValue) {
      if (profileAsync.hasError) {
        return _ProfileUnread(
          error: profileAsync.error!,
          busy: profileAsync.isLoading,
          onRetry: () => ref.invalidate(currentUserProfileProvider),
        );
      }
      return const _Loading();
    }
    final isCoach = profileAsync.value?['role'] == 'coach';
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
      loading: () => const _Loading(),
      error: (_, __) => child, // fail open rather than lock a paying user out
      data: (plan) =>
          plan.atLeast(required) ? child : PaywallLocked(required: required, feature: featureName),
    );
  }
}

/// The gate's one blocking spinner (first load only).
class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Scaffold(
      backgroundColor: _bg,
      body: Center(child: CircularProgressIndicator(color: _brand)));
}

/// P0-FL-44 · the profile could not be read, so it is not known whether this
/// is a coach (always in) or a client (plan decides). Say so, offer Try again
/// (busy-aware, via the shared notice) and a way back — neither the feature
/// nor the upgrade prompt. The failure itself is recorded by
/// `currentUserProfileProvider` (reportError), so it is not recorded again.
class _ProfileUnread extends StatelessWidget {
  const _ProfileUnread(
      {required this.error, required this.busy, required this.onRetry});
  final Object error;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: _white),
          leading: NamedIconButton(
            label: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
            child: const Icon(Icons.arrow_back, color: _white, size: 20),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ProfileLoadFailedNotice(
                error: error,
                busy: busy,
                detail: 'This feature stays closed until it loads.',
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      );
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
