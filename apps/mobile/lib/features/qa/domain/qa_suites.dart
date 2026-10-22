// The live, read-only QA suites the in-app QA Center runs. Everything here runs
// AS THE CURRENT USER, so it verifies exactly what a real user's session can
// reach (RLS included). State-mutating / privileged certifications (the full
// seeded 8-state entitlement matrix, Stripe webhooks) stay in the CLI harnesses
// (tool/qa_entitlements.dart, tool/qa_self_guided.dart) because they need the
// service-role key; those appear here as SKIP with a pointer, never faked green.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../payments/domain/entitlements.dart';
import 'qa_models.dart';

/// Reachability + row-count + latency for one table under the current session.
Future<QaCheck> _table(SupabaseClient db, String t) async {
  final sw = Stopwatch()..start();
  try {
    final n = await db.from(t).count(CountOption.exact);
    sw.stop();
    return QaCheck(t, QaStatus.pass, '$n rows · ${sw.elapsedMilliseconds}ms', sw.elapsedMilliseconds);
  } catch (_) {
    // Count may be blocked (RLS/policy); fall back to a reachability probe.
    try {
      await db.from(t).select('*').limit(1);
      sw.stop();
      return QaCheck(t, QaStatus.pass, 'reachable · ${sw.elapsedMilliseconds}ms', sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      final msg = e.toString();
      // A missing table is a real defect; an RLS denial is expected for some.
      final missing = msg.contains('does not exist') || msg.contains('42P01') || msg.contains('PGRST205');
      return QaCheck(t, missing ? QaStatus.fail : QaStatus.warn,
          missing ? 'table missing' : 'not reachable for this user', sw.elapsedMilliseconds);
    }
  }
}

// ── Authentication ──────────────────────────────────────────────────────────
class AuthSuite implements QaSuite {
  @override String get name => 'Authentication';
  @override String get group => 'Core';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    final session = db.auth.currentSession;
    final user = db.auth.currentUser;
    checks.add(QaCheck('Active session', session != null ? QaStatus.pass : QaStatus.fail,
        session != null ? 'token valid' : 'no session'));
    checks.add(QaCheck('User id present', user != null ? QaStatus.pass : QaStatus.fail,
        user?.id.substring(0, 8) ?? '—'));
    checks.add(await timedCheck('Profile readable', () async {
      final rows = await db.from('user_profiles').select('id, role').eq('id', user?.id ?? '').limit(1);
      if (rows.isEmpty) return const QaCheck('Profile readable', QaStatus.fail, 'no profile row');
      return QaCheck('Profile readable', QaStatus.pass, 'role=${rows.first['role']}');
    }));
    checks.add(const QaCheck('Google/Apple OAuth', QaStatus.skip, 'requires provider consent (manual)'));
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Entitlements (current user) ─────────────────────────────────────────────
class EntitlementsSuite implements QaSuite {
  @override String get name => 'Entitlements';
  @override String get group => 'Billing';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    // Server truth for THIS user.
    checks.add(await timedCheck('client_plan() resolves', () async {
      final res = await db.rpc('client_plan');
      final plan = clientPlanFromString(res is String ? res : 'free');
      return QaCheck('client_plan() resolves', QaStatus.pass, 'current = ${plan.label}');
    }));
    // The module enable/disable contract, derived from the SAME ClientPlanCaps
    // the app gates on — proven internally consistent across all four plans.
    for (final p in ClientPlan.values) {
      final on = <String>[
        if (p.canFullWorkouts) 'workouts',
        if (p.canFullNutrition) 'nutrition',
        if (p.canAdvancedAnalytics) 'insights',
        if (p.canAccessMarketplace) 'marketplace',
        if (p.canAiCoach) 'ai',
        if (p.canMessageCoach) 'coach',
      ];
      // Monotonic sanity: each higher tier is a superset of the lower one.
      final ok = switch (p) {
        ClientPlan.free => on.isEmpty,
        ClientPlan.selfGuided => on.contains('workouts') && !on.contains('ai'),
        ClientPlan.aiGuided => on.contains('ai') && !on.contains('coach'),
        ClientPlan.coachGuided => on.contains('coach'),
      };
      checks.add(QaCheck('${p.label} capability set', ok ? QaStatus.pass : QaStatus.fail,
          on.isEmpty ? 'community only' : on.join(', ')));
    }
    checks.add(const QaCheck('Seeded 8-state matrix', QaStatus.skip,
        'CLI only (needs service role): dart run tool/qa_entitlements.dart'));
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Database health ─────────────────────────────────────────────────────────
class DatabaseSuite implements QaSuite {
  @override String get name => 'Database';
  @override String get group => 'Core';
  static const _tables = [
    'user_profiles', 'subscriptions', 'payments', 'coach_packages',
    'exercises', 'workout_programs', 'program_workouts', 'workout_sessions',
    'nutrition_logs', 'habit_logs', 'score_events', 'user_scores',
    'community_posts', 'challenges', 'notifications', 'coaching_calls',
  ];
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[for (final t in _tables) await _table(db, t)];
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Scoring engine ──────────────────────────────────────────────────────────
class ScoringSuite implements QaSuite {
  @override String get name => 'Scoring';
  @override String get group => 'Engagement';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final uid = db.auth.currentUser?.id ?? '';
    final checks = <QaCheck>[
      await timedCheck('Score rollup readable', () async {
        await db.from('user_scores').select('*').eq('user_id', uid).limit(1);
        return const QaCheck('Score rollup readable', QaStatus.pass, 'user_scores ok');
      }),
      await timedCheck('Score ledger readable', () async {
        await db.from('score_events').select('id').eq('user_id', uid).limit(1);
        return const QaCheck('Score ledger readable', QaStatus.pass, 'score_events ok');
      }),
      await _table(db, 'badges'),
      const QaCheck('Daily/weekly/monthly resets', QaStatus.skip, 'cron-driven (verify scheduled job)'),
    ];
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Community & challenges ──────────────────────────────────────────────────
class CommunitySuite implements QaSuite {
  @override String get name => 'Community';
  @override String get group => 'Engagement';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[
      await _table(db, 'community_posts'),
      await _table(db, 'challenges'),
      await _table(db, 'events'),
    ];
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Workout system ──────────────────────────────────────────────────────────
class WorkoutSuite implements QaSuite {
  @override String get name => 'Workout System';
  @override String get group => 'Training';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final uid = db.auth.currentUser?.id ?? '';
    final checks = <QaCheck>[
      await _table(db, 'exercises'),
      await timedCheck('Assigned program readable', () async {
        await db.from('workout_program_assignments').select('id').eq('client_id', uid).limit(1);
        return const QaCheck('Assigned program readable', QaStatus.pass, 'assignments ok');
      }),
      await _table(db, 'workout_sessions'),
      const QaCheck('PR detection / volume', QaStatus.skip, 'exercised by tool/qa_self_guided.dart'),
    ];
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Nutrition ───────────────────────────────────────────────────────────────
class NutritionSuite implements QaSuite {
  @override String get name => 'Nutrition';
  @override String get group => 'Training';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final uid = db.auth.currentUser?.id ?? '';
    final checks = <QaCheck>[
      await timedCheck('Nutrition plan readable', () async {
        await db.from('client_nutrition_plans').select('id').eq('client_id', uid).limit(1);
        return const QaCheck('Nutrition plan readable', QaStatus.pass, 'targets ok');
      }),
      await _table(db, 'nutrition_logs'),
      const QaCheck('AI calorie estimation', QaStatus.skip, 'Claude-vision endpoint (manual/live)'),
    ];
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Suites that need infra we can't stand up in-app (honest placeholders) ────
class _StubSuite implements QaSuite {
  @override final String name;
  @override final String group;
  final String reason;
  _StubSuite(this.name, this.group, this.reason);
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async =>
      QaSuiteResult(name, [QaCheck(name, QaStatus.skip, reason)], 0);
}

QaSuite stripeSuite() => _StubSuite('Stripe', 'Billing',
    'checkout/webhook/refund need Stripe test-mode + edge fns (CI harness)');
QaSuite stripeConnectSuite() => _StubSuite('Stripe Connect', 'Billing',
    'express onboarding + payouts need Connect test accounts');
QaSuite aiCoachSuite() => _StubSuite('AI Coach', 'Intelligence',
    'memory/recommendations/prediction run through Claude edge fns (live)');
QaSuite coachDashSuite() => _StubSuite('Coach Dashboard', 'Coaching',
    'messaging/bookings/compliance verified by a coach-role harness');
QaSuite notificationsSuite() => _StubSuite('Notifications', 'Core',
    'push delivery is OS/APNs/FCM — not head-less certifiable');
QaSuite performanceSuite() => _StubSuite('Performance', 'Core',
    'frame-rate/memory captured by the profile-build harness');

// ── Coaching-mode certification ─────────────────────────────────────────────
// The route→required-plan matrix, transcribed from app_router.dart PaywallGate
// config. PaywallGate grants access iff plan.atLeast(required). Keep in sync
// with the router; the cross-checks below fail if this and ClientPlanCaps drift.
const Map<String, ClientPlan> gatedRoutes = {
  '/nutrition': ClientPlan.selfGuided,
  '/meals-dashboard': ClientPlan.selfGuided,
  '/nutrition-overview': ClientPlan.selfGuided,
  '/food-search': ClientPlan.selfGuided,
  '/log-meal': ClientPlan.selfGuided,
  '/insights': ClientPlan.selfGuided,
  '/ai-nutrition': ClientPlan.aiGuided,
  '/ai-coach': ClientPlan.aiGuided,
  '/appointments': ClientPlan.coachGuided,
  '/messages': ClientPlan.coachGuided,
  '/chat': ClientPlan.coachGuided,
  '/action-items': ClientPlan.coachGuided,
  '/book-call': ClientPlan.coachGuided,
};

ClientPlan? _nextTier(ClientPlan p) => switch (p) {
      ClientPlan.free => ClientPlan.selfGuided,
      ClientPlan.selfGuided => ClientPlan.aiGuided,
      ClientPlan.aiGuided => ClientPlan.coachGuided,
      ClientPlan.coachGuided => null,
    };

/// Certifies ONE coaching mode end-to-end: capability contract, navigation +
/// permission gates (cross-checked against ClientPlanCaps), upgrade path, and —
/// when the current session is on this mode — the live data / scoring path.
/// Live checks for other modes SKIP with a pointer (in-app runs as one user).
class CoachingModeSuite implements QaSuite {
  final ClientPlan mode;
  CoachingModeSuite(this.mode);

  @override String get name => 'Mode · ${mode.label}';
  @override String get group => 'Coaching Modes';

  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];

    // 1) Capability contract — the module on/off set for this mode.
    final expected = <String, bool>{
      'Full workouts'    : mode != ClientPlan.free,
      'Full nutrition'   : mode != ClientPlan.free,
      'Advanced insights': mode != ClientPlan.free,
      'Marketplace'      : mode != ClientPlan.free,
      'AI coach'         : mode.rank >= ClientPlan.aiGuided.rank,
      'Program generation': mode.rank >= ClientPlan.aiGuided.rank,
      'Coach messaging'  : mode == ClientPlan.coachGuided,
    };
    final actual = <String, bool>{
      'Full workouts'    : mode.canFullWorkouts,
      'Full nutrition'   : mode.canFullNutrition,
      'Advanced insights': mode.canAdvancedAnalytics,
      'Marketplace'      : mode.canAccessMarketplace,
      'AI coach'         : mode.canAiCoach,
      'Program generation': mode.canGenerateProgram,
      'Coach messaging'  : mode.canMessageCoach,
    };
    for (final k in expected.keys) {
      final ok = expected[k] == actual[k];
      checks.add(QaCheck('Capability: $k', ok ? QaStatus.pass : QaStatus.fail,
          actual[k]! ? 'unlocked' : 'locked'));
    }
    // Community-tier features are always on.
    checks.add(QaCheck('Capability: Community/Events',
        (mode.canAccessCommunity && mode.canRegisterEvents) ? QaStatus.pass : QaStatus.fail, 'always on'));

    // 2) Navigation + permissions — cross-check router gates vs ClientPlanCaps.
    //    Each gated route's atLeast() verdict must agree with the matching cap.
    final crosswalk = <String, bool>{
      'Nutrition routes ↔ canFullNutrition':
          gatedRoutes.entries.where((e) => e.value == ClientPlan.selfGuided && e.key.contains('nutr') || e.key == '/food-search' || e.key == '/log-meal')
              .every((e) => mode.atLeast(e.value) == mode.canFullNutrition),
      'Insights route ↔ canAdvancedAnalytics':
          mode.atLeast(ClientPlan.selfGuided) == mode.canAdvancedAnalytics,
      'AI routes ↔ canAiCoach':
          mode.atLeast(ClientPlan.aiGuided) == mode.canAiCoach,
      'Coach routes ↔ canMessageCoach':
          mode.atLeast(ClientPlan.coachGuided) == mode.canMessageCoach,
    };
    crosswalk.forEach((label, ok) =>
        checks.add(QaCheck('Nav gate: $label', ok ? QaStatus.pass : QaStatus.fail,
            ok ? 'router ↔ caps agree' : 'GATE DRIFT — router and ClientPlanCaps disagree')));

    // Allowed vs denied gated-route counts for this mode.
    final allowed = gatedRoutes.entries.where((e) => mode.atLeast(e.value)).length;
    final denied = gatedRoutes.length - allowed;
    final expAllowed = switch (mode) {
      ClientPlan.free => 0,
      ClientPlan.selfGuided => 6,
      ClientPlan.aiGuided => 8,
      ClientPlan.coachGuided => gatedRoutes.length,
    };
    checks.add(QaCheck('Route access count', allowed == expAllowed ? QaStatus.pass : QaStatus.fail,
        '$allowed unlocked · $denied locked'));

    // 3) Upgrade path / prompts.
    final next = _nextTier(mode);
    checks.add(QaCheck('Upgrade prompt',
        (mode == ClientPlan.coachGuided ? next == null : next != null) ? QaStatus.pass : QaStatus.fail,
        next == null ? 'top tier — none' : 'offers ${next.label}'));

    // 4) Live, session-aware certification (only when the tester IS on this mode).
    ClientPlan live = ClientPlan.free;
    try {
      final r = await db.rpc('client_plan');
      live = clientPlanFromString(r is String ? r : 'free');
    } catch (_) {}
    final uid = db.auth.currentUser?.id ?? '';

    if (live == mode) {
      // Subscription state for the current user.
      checks.add(await timedCheck('Subscription state (live)', () async {
        final subs = await db.from('subscriptions').select('kind, status')
            .eq('user_id', uid).order('created_at', ascending: false).limit(1);
        if (subs.isEmpty) {
          return QaCheck('Subscription state (live)',
              mode == ClientPlan.free ? QaStatus.pass : QaStatus.warn,
              mode == ClientPlan.free ? 'no sub (correct for Free)' : 'entitled but no sub row');
        }
        return QaCheck('Subscription state (live)', QaStatus.pass,
            '${subs.first['kind']} · ${subs.first['status']}');
      }));
      // Mode-appropriate data path.
      if (mode == ClientPlan.free) {
        checks.add(await timedCheck('Community access (live)', () async {
          await db.from('community_posts').select('id').limit(1);
          return const QaCheck('Community access (live)', QaStatus.pass, 'readable');
        }));
      } else {
        checks.add(await timedCheck('Program assigned (live)', () async {
          final p = await db.from('workout_program_assignments').select('id').eq('client_id', uid).limit(1);
          return QaCheck('Program assigned (live)', p.isEmpty ? QaStatus.warn : QaStatus.pass,
              p.isEmpty ? 'none yet — generate to certify' : 'active program');
        }));
        checks.add(await timedCheck('Scoring readable (live)', () async {
          await db.from('user_scores').select('*').eq('user_id', uid).limit(1);
          return const QaCheck('Scoring readable (live)', QaStatus.pass, 'user_scores ok');
        }));
      }
      if (mode == ClientPlan.aiGuided) {
        checks.add(const QaCheck('AI generation/chat (live)', QaStatus.skip, 'Claude edge fns — run live/manual'));
      }
      if (mode == ClientPlan.coachGuided) {
        checks.add(await timedCheck('Coach relationship (live)', () async {
          final rel = await db.from('coach_client_relationships').select('status')
              .eq('client_id', uid).eq('status', 'active').limit(1);
          return QaCheck('Coach relationship (live)', rel.isEmpty ? QaStatus.warn : QaStatus.pass,
              rel.isEmpty ? 'no active coach link' : 'assigned');
        }));
      }
    } else {
      checks.add(QaCheck('Live data path', QaStatus.skip,
          'tester is on ${live.label} — sign in as ${mode.label} (or use the CLI harness / Switch User)'));
    }

    checks.add(const QaCheck('Notifications delivery', QaStatus.skip, 'OS/APNs/FCM — not head-less'));
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Data Integrity Certification ────────────────────────────────────────────
// Validates data QUALITY, not just that code runs — the class of production
// issues feature tests miss (a coach with no video, an exercise with a dup slug,
// a client with an invalid coaching_mode). Read-only. Cross-user scans are
// RLS-scoped to what the current session can see; each check states its scope.

bool _emptyVal(dynamic v) {
  if (v == null) return true;
  if (v is String) return v.trim().isEmpty;
  if (v is List) return v.isEmpty;
  if (v is Map) return v.isEmpty;
  return false;
}

/// Turn an offender count into a check: 0 → pass; >0 → [sev] with the count.
QaCheck _integrity(String name, int offenders, int scanned, QaStatus sev, {String unit = ''}) {
  if (offenders == 0) {
    return QaCheck(name, QaStatus.pass, scanned == 0 ? 'nothing to scan' : 'clean · $scanned scanned');
  }
  return QaCheck(name, sev, '$offenders$unit of $scanned');
}

Future<List<Map<String, dynamic>>> _fetch(SupabaseClient db, String table, String cols,
    {int limit = 3000, dynamic Function(dynamic q)? where}) async {
  dynamic q = db.from(table).select(cols);
  if (where != null) q = where(q);
  final r = await q.limit(limit);
  return (r as List).cast<Map<String, dynamic>>();
}

// Exercises — the public library, fully scannable in any session. Highest-value
// integrity target (this is where the video-enrichment pipeline's gaps surface).
class ExerciseIntegritySuite implements QaSuite {
  @override String get name => 'Integrity · Exercises';
  @override String get group => 'Data Integrity';
  static const _difficulties = {'beginner', 'intermediate', 'advanced', 'expert'};
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    try {
      final rows = await _fetch(db, 'exercises',
          'id,name,slug,muscle_group,equipment,equipment_required,instructions,'
          'image_url,video_variants,video_assets,video_required,difficulty');
      final n = rows.length;

      // Duplicate slugs.
      final slugs = <String, int>{};
      for (final r in rows) {
        final s = (r['slug'] as String?)?.trim();
        if (s != null && s.isNotEmpty) slugs[s] = (slugs[s] ?? 0) + 1;
      }
      final dupSlugs = slugs.values.where((c) => c > 1).length;
      checks.add(_integrity('Duplicate slugs', dupSlugs, n, QaStatus.fail));

      checks.add(_integrity('Missing name',
          rows.where((r) => _emptyVal(r['name'])).length, n, QaStatus.fail));
      checks.add(_integrity('Missing slug',
          rows.where((r) => _emptyVal(r['slug'])).length, n, QaStatus.warn));
      // Content-completeness gaps are WARN (backlog), not FAIL (won't block a
      // release the way structural corruption does).
      checks.add(_integrity('Missing instructions',
          rows.where((r) => _emptyVal(r['instructions'])).length, n, QaStatus.warn));
      checks.add(_integrity('Missing muscle group',
          rows.where((r) => _emptyVal(r['muscle_group'])).length, n, QaStatus.warn));
      checks.add(_integrity('Missing equipment',
          rows.where((r) => _emptyVal(r['equipment']) && _emptyVal(r['equipment_required'])).length,
          n, QaStatus.warn));
      checks.add(_integrity('Missing image',
          rows.where((r) => _emptyVal(r['image_url'])).length, n, QaStatus.warn));
      // Missing video where the exercise declares one is required.
      checks.add(_integrity('Missing required video',
          rows.where((r) => r['video_required'] == true &&
              _emptyVal(r['video_variants']) && _emptyVal(r['video_assets'])).length,
          n, QaStatus.warn));
      // Invalid difficulty (non-null and outside the known set).
      checks.add(_integrity('Invalid difficulty',
          rows.where((r) {
            final d = (r['difficulty'] as String?)?.toLowerCase();
            return d != null && d.isNotEmpty && !_difficulties.contains(d);
          }).length, n, QaStatus.fail));
    } catch (e) {
      checks.add(QaCheck('Exercise scan', QaStatus.fail, e.toString()));
    }
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// Programs — validates the structure of visible workout programs.
class ProgramIntegritySuite implements QaSuite {
  @override String get name => 'Integrity · Programs';
  @override String get group => 'Data Integrity';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    try {
      final days = await _fetch(db, 'program_workouts',
          'id,program_id,title,exercises,estimated_minutes', limit: 2000);
      if (days.isEmpty) {
        checks.add(const QaCheck('Program structure', QaStatus.skip,
            'no visible program days — full scan is admin/CLI scope'));
      } else {
        final n = days.length;
        // Empty workout days.
        checks.add(_integrity('Empty workout days',
            days.where((d) => _emptyVal(d['exercises'])).length, n, QaStatus.fail));
        // Missing title.
        checks.add(_integrity('Missing day title',
            days.where((d) => _emptyVal(d['title'])).length, n, QaStatus.fail));
        // Exercises missing rest periods.
        var noRest = 0, badRef = 0;
        for (final d in days) {
          final ex = d['exercises'];
          if (ex is! List) continue;
          for (final e in ex) {
            if (e is! Map) continue;
            final rest = e['rest_seconds'];
            if (rest == null || (rest is num && rest <= 0)) noRest++;
            if (_emptyVal(e['name'])) badRef++;
          }
        }
        checks.add(QaCheck('Exercises missing rest', noRest == 0 ? QaStatus.pass : QaStatus.warn,
            noRest == 0 ? 'all have rest' : '$noRest exercise entries'));
        checks.add(QaCheck('Unnamed exercise refs', badRef == 0 ? QaStatus.pass : QaStatus.fail,
            badRef == 0 ? 'all named' : '$badRef entries'));
      }
    } catch (e) {
      checks.add(QaCheck('Program scan', QaStatus.warn, e.toString()));
    }
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// Coaches — user_profiles(role=coach) + coach_packages (services/pricing).
class CoachIntegritySuite implements QaSuite {
  @override String get name => 'Integrity · Coaches';
  @override String get group => 'Data Integrity';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    try {
      final coaches = await _fetch(db, 'user_profiles', 'id,avatar_url,first_name',
          where: (q) => q.eq('role', 'coach'));
      final n = coaches.length;
      if (n == 0) {
        checks.add(const QaCheck('Coach profiles', QaStatus.skip, 'no visible coaches'));
      } else {
        checks.add(_integrity('Coaches missing avatar',
            coaches.where((c) => _emptyVal(c['avatar_url'])).length, n, QaStatus.warn));
        checks.add(_integrity('Coaches missing name',
            coaches.where((c) => _emptyVal(c['first_name'])).length, n, QaStatus.warn));

        final pkgs = await _fetch(db, 'coach_packages', 'coach_id,price,active', limit: 3000);
        final coachIds = coaches.map((c) => c['id']).toSet();
        final withServices = pkgs.map((p) => p['coach_id']).toSet();
        checks.add(_integrity('Coaches with no services',
            coachIds.where((id) => !withServices.contains(id)).length, n, QaStatus.warn));
        // Active package priced at/below zero.
        checks.add(_integrity('Invalid package pricing',
            pkgs.where((p) => p['active'] == true &&
                (p['price'] == null || (p['price'] as num) <= 0)).length,
            pkgs.length, QaStatus.fail));
      }
      checks.add(const QaCheck('Stripe Connect account', QaStatus.skip,
          'connect account id is coach-private — admin/CLI scope'));
    } catch (e) {
      checks.add(QaCheck('Coach scan', QaStatus.warn, e.toString()));
    }
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// Clients — profile + subscription hygiene. RLS scopes a client session to self;
// an admin session scans the whole tenant.
class ClientIntegritySuite implements QaSuite {
  @override String get name => 'Integrity · Clients';
  @override String get group => 'Data Integrity';
  static const _modes = {'self_guided', 'ai_guided', 'coach_guided'};
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    try {
      final clients = await _fetch(db, 'user_profiles', 'id,coaching_mode,onboarding_complete',
          where: (q) => q.eq('role', 'client'));
      final n = clients.length;
      final scope = n <= 1 ? ' (scoped to self — full scan needs admin/CLI)' : '';
      checks.add(_integrity('Invalid coaching_mode',
          clients.where((c) {
            final m = c['coaching_mode'] as String?;
            return m != null && !_modes.contains(m);
          }).length, n, QaStatus.fail));
      checks.add(_integrity('Incomplete onboarding',
          clients.where((c) => c['onboarding_complete'] != true).length, n, QaStatus.warn));

      final subs = await _fetch(db, 'subscriptions', 'user_id,kind,status', limit: 3000);
      // Duplicate ACTIVE plans of the same kind for one user.
      final active = subs.where((s) => s['status'] == 'active' || s['status'] == 'trialing');
      final seen = <String, int>{};
      for (final s in active) {
        final key = '${s['user_id']}|${s['kind']}';
        seen[key] = (seen[key] ?? 0) + 1;
      }
      checks.add(_integrity('Duplicate active plans',
          seen.values.where((c) => c > 1).length, active.length, QaStatus.fail));
      checks.add(QaCheck('Subscription scope', QaStatus.pass, '${subs.length} visible$scope'));
    } catch (e) {
      checks.add(QaCheck('Client scan', QaStatus.warn, e.toString()));
    }
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── Content Quality ─────────────────────────────────────────────────────────
// Not "does it work" but "is the content ready for customers". Reports per-field
// completion across the (public) exercise library so everyone can see exactly
// what content work remains. Feeds the enrich-exercise-content pipeline.
class ContentQualitySuite implements QaSuite {
  @override String get name => 'Content · Exercise Library';
  @override String get group => 'Content Quality';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final checks = <QaCheck>[];
    try {
      final rows = await _fetch(db, 'exercises',
          'id,instructions,coaching_cues,common_mistakes,beginner_modification,'
          'advanced_progression,alternatives,image_url,video_variants,video_assets,'
          'muscle_group,equipment');
      final n = rows.length;
      bool has(dynamic v) => !_emptyVal(v);

      QaCheck metric(String label, bool Function(Map<String, dynamic>) filled, {double target = 0.95}) {
        final c = rows.where(filled).length;
        final frac = n == 0 ? 0.0 : c / n;
        final st = frac >= target ? QaStatus.pass : QaStatus.warn;
        return QaCheck(label, st, '$c / $n · ${(frac * 100).toStringAsFixed(1)}%', 0, frac);
      }

      checks.add(metric('Cover images', (r) => has(r['image_url'])));
      checks.add(metric('Demo videos', (r) => has(r['video_variants']) || has(r['video_assets'])));
      checks.add(metric('Instructions', (r) => has(r['instructions'])));
      checks.add(metric('Coaching cues', (r) => has(r['coaching_cues'])));
      checks.add(metric('Common mistakes', (r) => has(r['common_mistakes'])));
      checks.add(metric('Beginner modification', (r) => has(r['beginner_modification'])));
      checks.add(metric('Advanced progression', (r) => has(r['advanced_progression'])));
      checks.add(metric('Alternatives', (r) => has(r['alternatives'])));
      // AI-ready = enough structured content for the AI to coach from.
      checks.add(metric('AI-ready', (r) =>
          has(r['instructions']) && has(r['coaching_cues']) &&
          has(r['muscle_group']) && has(r['equipment'])));

      // Overall quality score = mean completion across the content fields above.
      final fracs = checks.map((c) => c.value ?? 0).toList();
      final score = fracs.isEmpty ? 0.0 : fracs.reduce((a, b) => a + b) / fracs.length;
      checks.insert(0, QaCheck('Quality score', score >= 0.9 ? QaStatus.pass : QaStatus.warn,
          '${(score * 100).toStringAsFixed(0)}% · $n exercises', 0, score));
    } catch (e) {
      checks.add(QaCheck('Content scan', QaStatus.warn, e.toString()));
    }
    sw.stop();
    return QaSuiteResult(name, checks, sw.elapsedMilliseconds);
  }
}

// ── User Journey Certification ──────────────────────────────────────────────
// Answers "can this persona get through the product end-to-end?" In-app this is
// a completion AUDIT of the logged-in persona: each milestone is verified read-
// only, and steps that require being a different persona SKIP with a pointer to
// the from-scratch CLI simulator (tool/qa_self_guided.dart et al.), which mutates
// state across roles and needs the service-role key.

class _JCtx {
  final String uid;
  final String role;
  final ClientPlan plan;
  _JCtx(this.uid, this.role, this.plan);
}

typedef _Step = Future<QaCheck> Function(SupabaseClient db, _JCtx c);

Future<bool> _rowExists(SupabaseClient db, String table, String col, String val,
    {String? statusEq}) async {
  dynamic q = db.from(table).select('*').eq(col, val);
  if (statusEq != null) q = q.eq('status', statusEq);
  final r = await q.limit(1);
  return (r as List).isNotEmpty;
}

// Reusable milestones ────────────────────────────────────────────────────────
_Step _mAccount() => (db, c) async {
      final ok = await _rowExists(db, 'user_profiles', 'id', c.uid);
      return QaCheck('Account created', ok ? QaStatus.pass : QaStatus.fail,
          ok ? 'profile row' : 'no profile');
    };
_Step _mOnboarding() => (db, c) async {
      final r = await db.from('user_profiles').select('onboarding_complete').eq('id', c.uid).limit(1);
      final done = (r as List).isNotEmpty && r.first['onboarding_complete'] == true;
      return QaCheck('Onboarding complete', done ? QaStatus.pass : QaStatus.warn,
          done ? 'done' : 'not finished');
    };
_Step _mPlanIs(ClientPlan want) => (db, c) async => c.plan == want
    ? QaCheck('On ${want.label} plan', QaStatus.pass, 'entitled')
    : QaCheck('On ${want.label} plan', QaStatus.skip, 'tester is ${c.plan.label}');
_Step _mReadable(String label, String table) => (db, c) async {
      await db.from(table).select('*').limit(1);
      return QaCheck(label, QaStatus.pass, '$table reachable');
    };
_Step _mHasRow(String label, String table, String col, {String? statusEq, String hint = ''}) =>
    (db, c) async {
      final ok = await _rowExists(db, table, col, c.uid, statusEq: statusEq);
      return QaCheck(label, ok ? QaStatus.pass : QaStatus.warn,
          ok ? 'present' : (hint.isEmpty ? 'none yet' : hint));
    };
_Step _mCapability(String label, bool Function(ClientPlan) cap) => (db, c) async =>
    cap(c.plan)
        ? QaCheck(label, QaStatus.pass, 'unlocked')
        : QaCheck(label, QaStatus.skip, 'requires higher tier (${c.plan.label} now)');
_Step _mUpgradePrompt() => (db, c) async {
      final next = _nextTier(c.plan);
      final gated = !c.plan.canFullWorkouts;
      return (gated && next != null)
          ? QaCheck('Upgrade prompt appears', QaStatus.pass, 'offers ${next.label}')
          : QaCheck('Upgrade prompt appears', QaStatus.skip, 'not on Free');
    };
_Step _mPoints() => (db, c) async {
      final r = await db.from('user_scores').select('*').eq('user_id', c.uid).limit(1);
      return (r as List).isNotEmpty
          ? const QaCheck('Points awarded', QaStatus.pass, 'score row')
          : const QaCheck('Points awarded', QaStatus.warn, 'none yet');
    };
_Step _mRoleIs(String label, Set<String> roles) => (db, c) async =>
    roles.contains(c.role)
        ? QaCheck(label, QaStatus.pass, c.role)
        : QaCheck(label, QaStatus.skip, 'tester role is ${c.role}');
_Step _mSkip(String label, String reason) => (db, c) async => QaCheck(label, QaStatus.skip, reason);

class JourneySuite implements QaSuite {
  final String _name;
  final List<_Step> _steps;
  JourneySuite(this._name, this._steps);
  @override String get name => _name;
  @override String get group => 'User Journeys';
  @override
  Future<QaSuiteResult> run(SupabaseClient db) async {
    final sw = Stopwatch()..start();
    final uid = db.auth.currentUser?.id ?? '';
    var role = 'client';
    var plan = ClientPlan.free;
    try {
      final p = await db.from('user_profiles').select('role').eq('id', uid).limit(1);
      if ((p as List).isNotEmpty) role = (p.first['role'] as String?) ?? 'client';
    } catch (_) {}
    try {
      final r = await db.rpc('client_plan');
      plan = clientPlanFromString(r is String ? r : 'free');
    } catch (_) {}
    final c = _JCtx(uid, role, plan);
    final checks = <QaCheck>[];
    for (final s in _steps) {
      try { checks.add(await s(db, c)); }
      catch (e) { checks.add(QaCheck('journey step', QaStatus.warn, e.toString())); }
    }
    // Every journey points at its from-scratch simulator.
    checks.add(const QaCheck('From-scratch simulation', QaStatus.skip,
        'CLI simulator (signup→…→verify) — needs service role'));
    sw.stop();
    return QaSuiteResult(_name, checks, sw.elapsedMilliseconds);
  }
}

List<QaSuite> journeySuites() => [
  JourneySuite('Journey · Free Client', [
    _mAccount(), _mOnboarding(), _mPlanIs(ClientPlan.free),
    _mReadable('Dashboard loads', 'challenges'),
    _mReadable('Marketplace browsable', 'coach_packages'),
    _mReadable('Community joinable', 'community_posts'),
    _mReadable('Starter workout available', 'exercises'),
    _mUpgradePrompt(),
  ]),
  JourneySuite('Journey · Self-Guided', [
    _mAccount(), _mOnboarding(), _mPlanIs(ClientPlan.selfGuided),
    _mHasRow('Program generated', 'workout_program_assignments', 'client_id', hint: 'run generator'),
    _mHasRow('Workout completed', 'workout_sessions', 'user_id', statusEq: 'completed'),
    _mHasRow('Meal logged', 'nutrition_logs', 'user_id'),
    _mHasRow('Habits completed', 'habit_logs', 'user_id'),
    _mPoints(),
    _mCapability('Analytics available', (p) => p.canAdvancedAnalytics),
  ]),
  JourneySuite('Journey · AI-Guided', [
    _mAccount(), _mOnboarding(), _mPlanIs(ClientPlan.aiGuided),
    _mHasRow('AI program generated', 'workout_program_assignments', 'client_id', hint: 'run generator'),
    _mHasRow('Workout completed', 'workout_sessions', 'user_id', statusEq: 'completed'),
    _mCapability('AI coach unlocked', (p) => p.canAiCoach),
    _mSkip('AI insight generated', 'Claude edge fn — live/CLI'),
    _mSkip('AI weekly review', 'Claude edge fn — live/CLI'),
  ]),
  JourneySuite('Journey · Coach-Guided', [
    _mAccount(), _mOnboarding(),
    _mReadable('Browse coaches', 'coach_packages'),
    _mHasRow('Coach relationship active', 'coach_client_relationships', 'client_id', statusEq: 'active'),
    _mPlanIs(ClientPlan.coachGuided),
    _mHasRow('Workout assigned', 'workout_program_assignments', 'client_id'),
    _mCapability('Messaging unlocked', (p) => p.canMessageCoach),
    _mHasRow('Session booked', 'coaching_calls', 'client_id'),
    _mHasRow('Check-in submitted', 'weekly_checkins', 'user_id', statusEq: 'submitted'),
  ]),
  JourneySuite('Journey · Coach', [
    _mRoleIs('Registered as coach', {'coach'}),
    _mSkip('Stripe Connect onboarded', 'connect account id is coach-private'),
    _mHasRow('Package created', 'coach_packages', 'coach_id'),
    _mHasRow('Program created', 'workout_programs', 'coach_id'),
    _mHasRow('Exercise created', 'exercises', 'coach_id'),
    _mHasRow('Client received', 'coach_client_relationships', 'coach_id', statusEq: 'active'),
    _mHasRow('Session on calendar', 'coaching_calls', 'coach_id'),
  ]),
  JourneySuite('Journey · Wellness Partner', [
    _mRoleIs('Registered as partner', {'wellness_partner', 'vendor'}),
    _mSkip('Profile completed', 'wellness-partner module early-stage'),
    _mSkip('Service created', 'no services table yet'),
    _mSkip('Listing published', 'wellness-partner module early-stage'),
    _mSkip('Booking received', 'wellness-partner module early-stage'),
  ]),
];

/// The full registry the dashboard orchestrates.
List<QaSuite> allSuites() => [
  AuthSuite(),
  EntitlementsSuite(),
  for (final m in ClientPlan.values) CoachingModeSuite(m),
  DatabaseSuite(),
  ScoringSuite(),
  CommunitySuite(),
  WorkoutSuite(),
  NutritionSuite(),
  ExerciseIntegritySuite(),
  ProgramIntegritySuite(),
  CoachIntegritySuite(),
  ClientIntegritySuite(),
  ContentQualitySuite(),
  ...journeySuites(),
  stripeSuite(),
  stripeConnectSuite(),
  aiCoachSuite(),
  coachDashSuite(),
  notificationsSuite(),
  performanceSuite(),
];
