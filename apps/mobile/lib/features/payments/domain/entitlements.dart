import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'payment_provider.dart';
import '../../auth/domain/auth_provider.dart';

/// The client's effective plan along the journey Free → Self → AI → Coach.
enum ClientPlan { free, selfGuided, aiGuided, coachGuided }

ClientPlan clientPlanFromString(String? s) => switch (s) {
      'coach_guided' => ClientPlan.coachGuided,
      'ai_guided' => ClientPlan.aiGuided,
      'self_guided' => ClientPlan.selfGuided,
      _ => ClientPlan.free,
    };

/// Capability gates, derived from the Free Plan strategy doc. Free includes
/// community, event registration, one starter program, basic progress + limited
/// nutrition; everything else requires an upgrade.
extension ClientPlanCaps on ClientPlan {
  bool get isPaid => this != ClientPlan.free;

  /// Rank for "do I meet at least tier X" comparisons.
  int get rank => switch (this) {
        ClientPlan.free => 0,
        ClientPlan.selfGuided => 1,
        ClientPlan.aiGuided => 2,
        ClientPlan.coachGuided => 3,
      };

  bool atLeast(ClientPlan other) => rank >= other.rank;

  // ── Free (always on) ──────────────────────────────────────────────
  bool get canAccessCommunity => true;
  bool get canRegisterEvents => true;
  bool get canTrackProgressBasic => true;

  // ── Self-Guided and up ────────────────────────────────────────────
  bool get canFullWorkouts => isPaid;          // beyond the 4-week starter
  bool get canFullNutrition => isPaid;         // free = limited tracking only
  bool get canAdvancedAnalytics => isPaid;     // Insights
  bool get canAccessMarketplace => isPaid;     // browse/engage coaches

  // ── AI-Guided and up ──────────────────────────────────────────────
  bool get canAiCoach => atLeast(ClientPlan.aiGuided);
  bool get canGenerateProgram => atLeast(ClientPlan.aiGuided);

  // ── Coach-Guided only ─────────────────────────────────────────────
  bool get canMessageCoach => this == ClientPlan.coachGuided;

  String get label => switch (this) {
        ClientPlan.free => 'Free',
        ClientPlan.selfGuided => 'Self-Guided',
        ClientPlan.aiGuided => 'AI-Guided',
        ClientPlan.coachGuided => 'Coach-Guided',
      };
}

/// The current client's effective plan (server-resolved via client_plan()).
final clientPlanProvider = FutureProvider<ClientPlan>((ref) async {
  // `client_plan()` answers for `auth.uid()`: the next account on the device
  // must not be gated by the previous one's plan.
  ref.watch(currentUserProvider);
  // Reuse the membership call path; client_plan() is the unified resolver.
  final svc = ref.watch(paymentServiceProvider);
  return clientPlanFromString(await svc.clientPlan());
});
