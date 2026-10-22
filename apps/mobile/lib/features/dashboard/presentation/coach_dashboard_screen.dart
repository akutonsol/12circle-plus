import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../../core/realtime/realtime.dart';
import '../../checkins/domain/checkin_provider.dart';
import '../../messaging/data/messaging_service.dart';
import '../../messaging/domain/messaging_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart';
import '../../coach/presentation/coach_business_screen.dart';
import '../../coach/presentation/coach_availability_screen.dart';
import 'client_detail_screen.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../domain/coach_triage_provider.dart';
import 'widgets/needs_you_today.dart';
import '../../checkins/domain/checkin_columns.dart';
import '../domain/session_as_log.dart';

const _bg      = Color(0xFF030303);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand   = Color(0xFFA855F7);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _primary = Color(0xFFDDB7FF);
const _tertiary= Color(0xFF6FFBBE);
const _error   = Color(0xFFFFB4AB);

// ── Providers ─────────────────────────────────────────────────────────────────
final _supabase = Supabase.instance.client;

final coachNotificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final uid = _supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value([]);
  try {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => List<Map<String, dynamic>>.from(rows))
        .handleError((_) => <Map<String, dynamic>>[]);
  } catch (_) {
    return Stream.value([]);
  }
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifs = ref.watch(coachNotificationsProvider).valueOrNull ?? [];
  return notifs.where((n) => n['read'] == false).length;
});

// F-15/F-16: the error propagates. These four reads ended `catch { return []; }`,
// so a failure reached `/coach-dashboard` as "no clients", "no check-ins" and
// "no workouts" — a coach told their whole roster had vanished. `clientIds
// .isEmpty` is still an early empty list, because having no clients IS a real
// answer and must stay distinguishable from the read having failed.
final coachClientsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  // Live: re-fetch when a relationship changes (new client, status flip).
  ref.watch(tableTickerProvider('coach_client_relationships'));
  {
    final coachId = _supabase.auth.currentUser?.id;
    if (coachId == null) return [];
    // Only fetch clients with an active relationship to this coach
    final rels = await _supabase
        .from('coach_client_relationships')
        .select('client_id')
        .eq('coach_id', coachId)
        .eq('status', 'active');
    final clientIds = (rels as List).map((r) => r['client_id'] as String).toList();
    if (clientIds.isEmpty) return [];
    final data = await _supabase
        .from('user_profiles')
        .select('id, first_name, last_name, email, avatar_url, role')
        .inFilter('id', clientIds);
    return List<Map<String, dynamic>>.from(data);
  }
});

// The signed-in coach's ACTIVE client ids (empty if none).
Future<List<String>> _coachClientIds() async {
  final coachId = _supabase.auth.currentUser?.id;
  if (coachId == null) return [];
  final rels = await _supabase
      .from('coach_client_relationships')
      .select('client_id')
      .eq('coach_id', coachId)
      .eq('status', 'active');
  return (rels as List).map((r) => r['client_id'] as String).toList();
}

Widget _riskPill(String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20),
    border: Border.all(color: color.withValues(alpha: 0.4))),
  child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)));

// AI coaching signals for the coach's active clients (risk/adherence/last brief).
final coachAiSignalsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(tableTickerProvider('coach_client_relationships'));
  final data = await _supabase.rpc('coach_client_ai_signals');
  return List<Map<String, dynamic>>.from(data as List);
});

final clientCheckinsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  {
    final ids = await _coachClientIds();
    if (ids.isEmpty) return []; // no clients → no data (was showing ALL platform check-ins)
    // PD-B01: there is no daily check-in. This read `checkins`, which has never
    // existed, so the coach's check-in panel was permanently empty. It now reads
    // the table the member screen actually writes: check-ins SUBMITTED THIS
    // WEEK. The stat it feeds is labelled "Checked In", not "today", so no
    // wording had to change.
    final today = DateTime.now();
    final weekStart = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final data = await _supabase
        .from('weekly_checkins')
        .select()
        .inFilter('user_id', ids)
        .eq('status', 'submitted')
        .gte('week_start_date', weekStart.toIso8601String().split('T')[0])
        .order('submitted_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }
});

/// The coach's clients' completed sessions this week.
///
/// ── WHY THIS READS `workout_sessions` AND NOT `workout_logs` ──────────────
/// `workout_logs` carries **one** policy — `003:193`,
/// `USING (user_id = auth.uid())` — and no coach clause exists in any of the
/// 131 migrations. An RLS-filtered SELECT is not an error: PostgREST answers
/// `200` with `[]`. So this provider returned an empty list for **every coach,
/// always**, and `_buildWorkoutsTab` rendered "No workouts this week" as a
/// fact. Not a failure a retry could fix — a confident, permanent, wrong zero.
///
/// `workout_sessions` answers the same question and a coach is **authorized**
/// to ask it: `100_rls_harden_client_data.sql` grants
/// `USING (user_id = auth.uid() OR public.is_active_coach_of(user_id))`
/// FOR SELECT. That helper binds `coach_id` to `auth.uid()` and requires an
/// active relationship row, and `113:223` revokes `authenticated` from
/// `coach_client_relationships` entirely — so unlike F-21's shape, the caller
/// cannot forge the relationship that would satisfy it.
///
/// Both tables are written on the same completion — `active_workout_screen`
/// calls `logWorkout()` at :649 and `completeSession()` at :653 — so nothing
/// is lost by reading the one a coach may actually see.
///
/// Two deliberate narrowings:
///
///   * **`status = 'completed'`.** The table also holds `in_progress` and
///     `abandoned` rows, whose `completed_at` is null. Unfiltered, the tab's
///     `w['completed_at'] != null ? parse : DateTime.now()` fallback would
///     render an abandoned session as "0m ago" — a workout the client did not
///     finish, shown as one they just did.
///   * **explicit columns.** `workout_sessions` has gained five columns since
///     001 (`workout_name`, `total_exercises`, `total_sets`, `completed_sets`,
///     `calories_burned`). A bare `select()` would have pulled each one into a
///     coach surface as it landed, with nobody deciding.
final clientWorkoutLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  {
    final ids = await _coachClientIds();
    if (ids.isEmpty) return []; // no clients → no data (was showing ALL platform workouts)
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final data = await _supabase
        .from('workout_sessions')
        .select('user_id, workout_title, completed_at, duration_seconds')
        .inFilter('user_id', ids)
        .eq('status', 'completed')
        .gte('completed_at', start.toIso8601String())
        .order('completed_at', ascending: false);
    // `duration_seconds` here; `duration_minutes` on the old table. Converted
    // at the boundary so the four call sites below are untouched.
    return [
      for (final row in data as List)
        sessionAsWorkoutLog(Map<String, dynamic>.from(row as Map))
    ];
  }
});

// ── Coach Dashboard Screen ────────────────────────────────────────────────────
class CoachDashboardScreen extends ConsumerStatefulWidget {
  const CoachDashboardScreen({super.key});
  @override
  ConsumerState<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends ConsumerState<CoachDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    // Force refresh on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(coachClientsProvider);
      ref.invalidate(clientCheckinsProvider);
      ref.invalidate(clientWorkoutLogsProvider);
      ref.invalidate(coachSubmittedCheckinsProvider);
      ref.invalidate(pendingRequestsProvider);
      ref.invalidate(coachLeaderboardProvider);
    });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final clients  = ref.watch(coachClientsProvider);
    final checkins = ref.watch(clientCheckinsProvider);
    final workouts = ref.watch(clientWorkoutLogsProvider);

    // F-15: a failed read must not become "no clients". These three reads
    // decide what a coach is told about their entire roster, and a failure
    // arriving as an empty list told them it had vanished. `.valueOrNull` is
    // kept — these are the reads EC-G8 already counts — but a failure is now
    // tracked alongside it so the screen can tell the two apart.
    final failed = clients is AsyncError ||
        checkins is AsyncError ||
        workouts is AsyncError;
    final clientList    = clients is AsyncError ? const <Map<String, dynamic>>[] : (clients.valueOrNull  ?? []);
    final checkinList   = checkins is AsyncError ? const <Map<String, dynamic>>[] : (checkins.valueOrNull ?? []);
    final workoutList   = workouts is AsyncError ? const <Map<String, dynamic>>[] : (workouts.valueOrNull ?? []);

    // Stats
    final checkedInThisWeek = checkinList.map((c) => c['user_id']).toSet().length;
    final needsAttention  = checkinList.where((c) =>
      (checkinEnergy(c)?.toInt() ?? 5) <= 2 || (c['stress_level'] as int? ?? 0) >= 4).length;
    final workoutsThisWeek = workoutList.length;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF160E26), Color(0xFF0A0712), _card]),
            border: Border(bottom: BorderSide(color: _border))),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () => context.push('/profile'),
                child: Container(
                  width: 44, height: 44,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_brand, Color(0xFF6FFBBE)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFF2A1A4E)),
                    child: ClipOval(
                      child: () {
                        final av = (ref.watch(currentUserProfileProvider).valueOrNull?['avatar_url'] as String?)?.trim();
                        return (av != null && av.isNotEmpty)
                          ? Image.network(av, fit: BoxFit.cover, width: 40, height: 40,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person, color: _primary, size: 22))
                          : const Icon(Icons.person, color: _primary, size: 22);
                      }())),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Coach Dashboard",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _white, fontSize: 17,
                      fontWeight: FontWeight.w700)),
                  Text(ref.watch(currentUserDisplayNameProvider),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _primary.withValues(alpha: 0.7), fontSize: 12)),
                ]),
              ),
              const Spacer(),
              // FIT-032 declares "Messages" and "Notifications" as named
              // controls. The bell shipped as a bare GestureDetector + Icon —
              // an A-G8 site, and the coverage tool read it as present only
              // because `Icons.notifications_outlined` contains the word.
              NamedIconButton(
                label: 'Messages',
                onTap: () => context.go('/messages'),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.chat_bubble_outline,
                      color: _white, size: 18)),
              ),
              const SizedBox(width: 8),
              // Notification bell
              NamedIconButton(
                label: 'Notifications',
                onTap: () => _showNotificationsSheet(context),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.notifications_outlined, color: _white, size: 18)),
                    if (ref.watch(unreadNotificationCountProvider) > 0)
                      Positioned(
                        top: -2, right: -2,
                        child: Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(
                            color: _error,
                            shape: BoxShape.circle,
                            border: Border.all(color: _card, width: 1.5)),
                          alignment: Alignment.center,
                          child: Text(
                            ref.watch(unreadNotificationCountProvider) > 9
                                ? '9+' : '${ref.watch(unreadNotificationCountProvider)}',
                            style: const TextStyle(color: Colors.white,
                              fontSize: 8, fontWeight: FontWeight.w800)))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // All coach tools live behind one menu — keeps the header clean
              // and overflow-proof on any width.
              GestureDetector(
                onTap: () => _showCoachToolsSheet(context, ref),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_brand, Color(0xFF6D28D9)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: _brand.withValues(alpha: 0.45),
                      blurRadius: 12, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.grid_view_rounded, color: _white, size: 18))),
            ]),
            const SizedBox(height: 14),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(color: _brand, width: 3),
                insets: EdgeInsets.symmetric(horizontal: 4)),
              labelColor: _white,
              unselectedLabelColor: _muted,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: [
                const Tab(text: "Clients"),
                Tab(text: ref.watch(pendingRequestsProvider).valueOrNull?.isNotEmpty == true
                  ? "Requests ●" : "Requests"),
                const Tab(text: "Check-Ins"),
                const Tab(text: "Workouts"),
                const Tab(text: "Leaderboard"),
              ]),
          ])),

        // ── Summary strip ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF08050F),
          child: Row(children: [
            _SummaryChip(
              icon: Icons.people_outline,
              label: "Clients",
              value: "${clientList.length}",
              color: _primary),
            const SizedBox(width: 8),
            _SummaryChip(
              icon: Icons.check_circle_outline,
              label: "Checked In",
              value: "$checkedInThisWeek",
              color: _tertiary),
            const SizedBox(width: 8),
            _SummaryChip(
              icon: Icons.warning_amber_outlined,
              label: "Needs Attention",
              value: "$needsAttention",
              color: needsAttention > 0 ? _error : _muted),
            const SizedBox(width: 8),
            _SummaryChip(
              icon: Icons.fitness_center_outlined,
              label: "Workouts",
              value: "$workoutsThisWeek",
              color: _brand),
          ])),

        // ── Tab views ──
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildClientsTab(clientList, checkinList, workoutList, failed: failed),
              _buildRequestsTab(),
              _buildCheckinsTab(checkinList, clientList),
              _buildWorkoutsTab(workoutList, clientList),
              _buildLeaderboardTab(),
            ])),
      ])));
  }

  void _showNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(
        onMarkRead: (id) async {
          await _supabase.from('notifications').update({'read': true}).eq('id', id);
        },
        onMarkAllRead: () async {
          final uid = _supabase.auth.currentUser?.id;
          if (uid != null) {
            await _supabase
                .from('notifications')
                .update({'read': true})
                .eq('recipient_id', uid)
                .eq('read', false);
          }
        },
        onDelete: (id) async {
          await _supabase.from('notifications').delete().eq('id', id);
        },
        onClearAll: () async {
          final uid = _supabase.auth.currentUser?.id;
          if (uid != null) {
            await _supabase.from('notifications').delete().eq('recipient_id', uid);
          }
        },
      ),
    );
  }

  void _showCoachToolsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.8),
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border))),
        padding: EdgeInsets.fromLTRB(20, 12, 20,
            28 + MediaQuery.of(sheetCtx).padding.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2))),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Coach Tools',
              style: const TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w800))),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: [
              _toolTile(sheetCtx, Icons.calendar_month_rounded, 'Availability', const Color(0xFF6FFBBE),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoachAvailabilityScreen()))),
              _toolTile(sheetCtx, Icons.business_center_rounded, 'Business', const Color(0xFFDDB7FF),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoachBusinessScreen()))),
              _toolTile(sheetCtx, Icons.fact_check_rounded, 'Compliance', const Color(0xFFFFD479),
                () => context.push('/compliance')),
              _toolTile(sheetCtx, Icons.auto_awesome_rounded, 'Copilot', const Color(0xFFB76DFF),
                () => context.push('/coach-copilot')),
              _toolTile(sheetCtx, Icons.calendar_view_week_rounded, 'Program AI', const Color(0xFFA855F7),
                () => context.push('/program-designer')),
              _toolTile(sheetCtx, Icons.sync_rounded, 'Adapt', const Color(0xFF6FFBBE),
                () => context.push('/continuous-coaching')),
              _toolTile(sheetCtx, Icons.rate_review_rounded, 'Reviews', const Color(0xFFFFD479),
                () => context.push('/weekly-review')),
              _toolTile(sheetCtx, Icons.library_books_rounded, 'Programs', const Color(0xFFA855F7),
                () => context.push('/program-builder')),
              _toolTile(sheetCtx, Icons.fitness_center_rounded, 'Exercises', const Color(0xFFB76DFF),
                () => context.push('/exercise-database')),
              _toolTile(sheetCtx, Icons.workspace_premium_rounded, 'My Plan', const Color(0xFFFFD479),
                () => context.push('/coach-plan')),
              _toolTile(sheetCtx, Icons.payments_rounded, 'Packages', const Color(0xFF6FFBBE),
                () => context.push('/coach-packages')),
              _toolTile(sheetCtx, Icons.account_balance_wallet_rounded, 'Payments', const Color(0xFF6FFBBE),
                () => context.push('/coach-payments')),
              _toolTile(sheetCtx, Icons.groups_rounded, 'Classes', const Color(0xFF60A5FA),
                () => context.push('/coach-classes')),
              _toolTile(sheetCtx, Icons.refresh_rounded, 'Refresh', const Color(0xFFADC6FF), () {
                ref.invalidate(coachClientsProvider);
                ref.invalidate(clientCheckinsProvider);
                ref.invalidate(clientWorkoutLogsProvider);
                ref.invalidate(coachSubmittedCheckinsProvider);
              }),
            ]),
        ]))),
    );
  }

  Widget _toolTile(BuildContext sheetCtx, IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { Navigator.pop(sheetCtx); onTap(); },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF08050F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w600)),
        ])),
    );
  }

  Widget _buildClientsTab(
    List<Map<String, dynamic>> clients,
    List<Map<String, dynamic>> checkins,
    List<Map<String, dynamic>> workouts, {
    required bool failed,
  }) {
    // Client Intelligence metrics
    final highRisk = clients.where((c) => c['risk_level'] == 'high').length;
    final modRisk  = clients.where((c) => c['risk_level'] == 'moderate').length;
    final atRisk   = highRisk + modRisk;
    final missedCheckin = clients.where((c) {
      final uid = c['id'] as String;
      return !checkins.any((ch) => ch['user_id'] == uid);
    }).length;

    // AI Recommendations (rule-based from aggregate data)
    final aiRecs = _generateCoachRecs(clients, checkins, workouts);

    if (failed) {
      // NOT "No clients found". A coach whose roster read failed is being told
      // their clients have gone, which is both false and alarming. The line
      // follows the `Could not load [noun]` pattern this repository renders in
      // fifteen files; "Try again" is the package's own label.
      return _EmptyState(
        icon: Icons.cloud_off_rounded,
        message: "Could not load your clients",
        sub: "Pull to refresh to try again");
    }
    if (clients.isEmpty) {
      return _EmptyState(
        icon: Icons.people_outline,
        message: "No clients found",
        sub: "Clients will appear here when they sign up");
    }
    return RefreshIndicator(
      color: _brand,
      backgroundColor: _card,
      onRefresh: () async {
        ref.invalidate(coachClientsProvider);
        ref.invalidate(clientCheckinsProvider);
        ref.invalidate(clientWorkoutLogsProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: clients.length + 1,
        itemBuilder: (_, i) {
          // ── Client Intelligence header (index 0) ──
          if (i == 0) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── FIT-032 · "Needs you today" ────────────────────────────
              // The board's triage surface, added ABOVE the roster rather
              // than replacing it: this screen carries a coach's only path
              // to invites and pending requests, which the board does not
              // draw, and removing a capability because a frame omits it is
              // the mistake OD-15 records.
              //
              // The two thresholds are stated HERE, at the call site, so the
              // choice is visible in the diff. Neither is the board's — it
              // shows `9 days` and `Sunday` as sample values, not rules —
              // and both are recorded as OD-21.
              ref.watch(coachTriageSignalsProvider).when(
                loading: () => const SizedBox.shrink(),
                // A failed read must not read as "nothing needs you". That
                // is F-15 on the screen F-15 was found on.
                error: (_, __) => const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text("Couldn't load what needs you today",
                      style: TextStyle(color: _muted, fontSize: 13)),
                ),
                data: (signals) => Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: NeedsYouToday(
                    clients: signals,
                    totalClients: clients.length,
                    inactivityDays: 9,
                    blockEndHorizonDays: 7,
                  ),
                ),
              ),
              // Section header
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  const Icon(Icons.auto_awesome, color: _brand, size: 14),
                  const SizedBox(width: 6),
                  const Text('CLIENT INTELLIGENCE',
                    style: TextStyle(color: _brand, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                ])),
              // Metrics row — 5 chips: Total, At-Risk, High Risk, Missed Check-Ins, AI Recs
              Wrap(spacing: 6, runSpacing: 6, children: [
                _IntelChip('Total',        '${clients.length}',  Icons.people_outline,              _primary),
                _IntelChip('At-Risk',      '$atRisk',            Icons.report_problem_outlined,      _error),
                _IntelChip('High Risk',    '$highRisk',          Icons.health_and_safety_outlined,   const Color(0xFFFFB4AB)),
                _IntelChip('Missed CI',    '$missedCheckin',     Icons.event_busy_outlined,          _muted),
                _IntelChip('AI Recs',      '${aiRecs.length}',   Icons.auto_awesome,                _brand),
              ]),
              const SizedBox(height: 12),

              // High risk alert banner
              if (highRisk > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _error.withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: _error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '$highRisk client${highRisk > 1 ? 's' : ''} flagged HIGH RISK — review PAR-Q before programming.',
                      style: const TextStyle(color: _error, fontSize: 12, fontWeight: FontWeight.w600))),
                  ])),

              // ── AI Coach signals (risk + adherence from the AI engine) ──
              ref.watch(coachAiSignalsProvider).maybeWhen(
                data: (sigs) {
                  final flagged = sigs.where((s) =>
                    ((s['churn_risk'] as num?) ?? 0) >= 50 ||
                    ((s['injury_risk'] as num?) ?? 0) >= 50).toList();
                  if (flagged.isEmpty) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _brand.withValues(alpha: 0.25))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.health_and_safety_rounded, color: _brand, size: 13),
                        SizedBox(width: 6),
                        Text('AI COACH SIGNALS',
                          style: TextStyle(color: _brand, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ]),
                      const SizedBox(height: 8),
                      ...flagged.map((s) {
                        final churn = (s['churn_risk'] as num?)?.round() ?? 0;
                        final injury = (s['injury_risk'] as num?)?.round() ?? 0;
                        final w7 = (s['workouts_7d'] as num?)?.round() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(s['client_name']?.toString() ?? 'Client',
                                style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w700))),
                              if (churn >= 50) _riskPill('Drop-off $churn%', _error),
                              if (injury >= 50) ...[const SizedBox(width: 6), _riskPill('Injury $injury%', const Color(0xFFF59E0B))],
                            ]),
                            const SizedBox(height: 2),
                            Text('$w7 workout${w7 == 1 ? '' : 's'} this week'
                              '${s['risk_summary'] != null ? ' · ${s['risk_summary']}' : ''}',
                              style: const TextStyle(color: _muted, fontSize: 11, height: 1.3)),
                          ]));
                      }),
                    ]));
                },
                orElse: () => const SizedBox.shrink()),

              // AI Recommendations list
              if (aiRecs.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _brand.withValues(alpha: 0.2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, color: _brand, size: 13),
                      const SizedBox(width: 6),
                      const Text('AI RECOMMENDATIONS',
                        style: TextStyle(color: _brand, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    ]),
                    const SizedBox(height: 8),
                    ...aiRecs.map((rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('• ', style: TextStyle(color: _brand, fontSize: 12)),
                        Expanded(child: Text(rec,
                          style: const TextStyle(color: _white, fontSize: 12, height: 1.4))),
                      ]))),
                  ])),
                const SizedBox(height: 10),
              ],

              // Coach Success Metrics
              _CoachSuccessMetrics(clients: clients, checkins: checkins, workouts: workouts),
              const SizedBox(height: 10),

              const Divider(color: Color(0xFF1A1020)),
              const SizedBox(height: 4),
              const Text('ALL CLIENTS',
                style: TextStyle(color: _muted, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
            ]);
          }
          final client = clients[i - 1];
          final userId = client['id'] as String;
          final checkin = checkins.where((c) => c['user_id'] == userId).firstOrNull;
          final workoutCount = workouts.where((w) => w['user_id'] == userId).length;
          final hasCheckedIn = checkin != null;
          final energy = (checkin == null ? null : checkinEnergy(checkin))?.toInt() ?? 0;
          final stress = checkin?['stress_level'] as int? ?? 0;
          final needsAttention = hasCheckedIn && (energy <= 2 || stress >= 4);

          return GestureDetector(
            onTap: () {
              final name = '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim();
              Navigator.push(context, MaterialPageRoute(builder: (_) =>
                ClientDetailScreen(clientId: userId, clientName: name.isEmpty ? 'Client' : name)));
            },
            child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: needsAttention
                  ? _error.withValues(alpha: 0.4)
                  : _border)),
            child: Column(children: [
              Row(children: [
                // Avatar
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _brand.withValues(alpha: 0.15),
                    border: Border.all(color: _brand.withValues(alpha: 0.3))),
                  alignment: Alignment.center,
                  child: Text(
                    ((client['first_name'] as String? ?? 'C').isNotEmpty
                      ? client['first_name'] as String
                      : 'C')[0].toUpperCase(),
                    style: const TextStyle(color: _brand, fontSize: 18,
                      fontWeight: FontWeight.w800))),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim().isEmpty ? 'Client' : '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim(),
                      style: const TextStyle(color: _white, fontSize: 15,
                        fontWeight: FontWeight.w700)),
                    Text(client['email'] ?? '',
                      style: TextStyle(color: _muted.withValues(alpha: 0.5),
                        fontSize: 11)),
                  ])),
                // Status badges
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (needsAttention)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _error.withValues(alpha: 0.4))),
                      child: const Text("⚠️ Needs Attention",
                        style: TextStyle(color: _error, fontSize: 9,
                          fontWeight: FontWeight.w700)))
                  else if (hasCheckedIn)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _tertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _tertiary.withValues(alpha: 0.3))),
                      child: const Text("✓ Checked In",
                        style: TextStyle(color: _tertiary, fontSize: 9,
                          fontWeight: FontWeight.w700)))
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _border)),
                      child: Text("No check-in",
                        style: TextStyle(color: _muted.withValues(alpha: 0.5),
                          fontSize: 9, fontWeight: FontWeight.w600))),
                ]),
              ]),
              if (hasCheckedIn) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MiniStat("Mood",   "${checkin['mood'] ?? '-'}/5",    Icons.sentiment_satisfied_outlined, _primary),
                      _MiniStat("Energy", "${energy}/5",                      Icons.bolt,                         energy <= 2 ? _error : _tertiary),
                      _MiniStat("Stress", "${stress}/5",                      Icons.psychology_outlined,           stress >= 4 ? _error : _muted),
                      _MiniStat("Sleep",  "${checkinSleepHours(checkin) ?? '-'}h",Icons.bedtime_outlined,             _primary),
                      _MiniStat("Workouts","$workoutCount",                    Icons.fitness_center_outlined,      _brand),
                    ])),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final clientId  = client['id'] as String;
                      final clientFn  = client['first_name'] as String? ?? '';
                      final clientLn  = client['last_name'] as String? ?? '';
                      final convId = await MessagingService()
                          .getOrCreateCoachClientConversation(clientId);
                      // `mounted`, not `context.mounted`: this closure captures
                      // the STATE's context, and for a State the lint wants the
                      // State's own liveness. The two are equivalent here —
                      // State.mounted is State.context.mounted — so this is the
                      // idiomatic spelling, not a suppression.
                      if (!mounted) return;
                      ref.read(selectedConversationProvider.notifier).state = {
                        'id': convId,
                        'participant': {
                          'id': clientId,
                          'first_name': clientFn,
                          'last_name': clientLn,
                          'role': 'client',
                        },
                      };
                      context.go('/chat');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _brand.withValues(alpha: 0.3))),
                      alignment: Alignment.center,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.chat_bubble_outline, color: _brand, size: 14),
                        const SizedBox(width: 5),
                        Text("Message", style: TextStyle(color: _brand,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                      ])))),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border)),
                    alignment: Alignment.center,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.bar_chart, color: _muted.withValues(alpha: 0.6), size: 14),
                      const SizedBox(width: 5),
                      Text("Progress", style: TextStyle(color: _muted.withValues(alpha: 0.6),
                        fontSize: 12, fontWeight: FontWeight.w600)),
                    ]))),
              ]),
            ])));
        }));
  }

  Widget _buildRequestsTab() {
    final requestsAsync = ref.watch(pendingRequestsProvider);
    final invitesAsync = ref.watch(sentInvitesProvider);
    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
      error: (e, _) => _EmptyState(icon: Icons.inbox_outlined, message: 'Error loading requests', sub: e.toString()),
      data: (requests) {
        final invites = invitesAsync.valueOrNull ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            // Invite button
            GestureDetector(
              onTap: () => _showInviteSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _brand.withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.person_add_outlined, color: _brand, size: 18),
                  const SizedBox(width: 10),
                  const Text('Invite Client by Email', style: TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, color: _muted, size: 14),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // Pending requests section
            if (requests.isNotEmpty) ...[
              const Text('Pending Requests', style: TextStyle(color: _muted, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ...requests.map((req) {
                final profile = req['profile'] as Map<String, dynamic>? ?? {};
                final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
                final goal = profile['fitness_goal'] as String? ?? '';
                final msg = req['request_message'] as String?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _brand.withValues(alpha: 0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _brand.withValues(alpha: 0.15)),
                        alignment: Alignment.center,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
                          style: const TextStyle(color: _brand, fontSize: 18, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name.isEmpty ? 'New Client' : name,
                          style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(goal.isEmpty ? profile['email'] as String? ?? '' : _goalLabel(goal),
                          style: const TextStyle(color: _muted, fontSize: 12)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _tertiary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _tertiary.withValues(alpha: 0.3))),
                        child: const Text('Pending', style: TextStyle(color: _tertiary, fontSize: 10, fontWeight: FontWeight.w700))),
                    ]),
                    if (msg != null && msg.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10)),
                        child: Text('"$msg"', style: const TextStyle(color: _muted, fontSize: 13, fontStyle: FontStyle.italic))),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: GestureDetector(
                        onTap: () => _declineRequest(req['id'] as String, req['client_id'] as String),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _error.withValues(alpha: 0.3))),
                          alignment: Alignment.center,
                          child: const Text('Decline', style: TextStyle(color: _error, fontSize: 13, fontWeight: FontWeight.w700))))),
                      const SizedBox(width: 10),
                      Expanded(child: GestureDetector(
                        onTap: () => _approveRequest(req['id'] as String, req['client_id'] as String),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [_brand, Color(0xFF6FFBBE)]),
                            borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: const Text('Accept', style: TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w700))))),
                    ]),
                  ]),
                );
              }),
              const SizedBox(height: 8),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: const Text('No pending requests', style: TextStyle(color: _muted, fontSize: 14)),
              ),
            ],

            // Sent invites section
            if (invites.isNotEmpty) ...[
              const Text('SENT INVITES', style: TextStyle(color: _muted, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ...invites.map((inv) {
                final email = inv['invitee_email'] as String? ?? '';
                final status = inv['status'] as String? ?? 'pending';
                final raw = inv['created_at'] as String?;
                final dt = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
                final age = dt != null ? DateTime.now().difference(dt) : Duration.zero;
                final ageStr = age.inDays > 0 ? '${age.inDays}d ago' : 'Today';
                final statusColor = status == 'accepted'
                    ? const Color(0xFF4ADE80)
                    : status == 'expired' ? _error : _tertiary;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A3D))),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        color: statusColor.withValues(alpha: 0.1)),
                      child: Icon(Icons.email_outlined, color: statusColor, size: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(email, style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Sent $ageStr', style: const TextStyle(color: _muted, fontSize: 11)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700))),
                  ]),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Future<void> _approveRequest(String relId, String clientId) async {
    await ref.read(coachRelServiceProvider).approveRequest(relId, clientId);
    ref.invalidate(pendingRequestsProvider);
    ref.invalidate(coachClientsProvider);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Client accepted!'), backgroundColor: _brand));
  }

  Future<void> _declineRequest(String relId, String clientId) async {
    await ref.read(coachRelServiceProvider).declineRequest(relId, clientId);
    ref.invalidate(pendingRequestsProvider);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request declined'), backgroundColor: Color(0xFF333333)));
  }

  void _showInviteSheet(BuildContext context) {
    final emailCtrl = TextEditingController();
    bool sending = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Invite a Client', style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text("We'll send them an email with your invite link", style: TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: _white),
            decoration: InputDecoration(
              hintText: 'client@email.com', hintStyle: const TextStyle(color: _muted),
              prefixIcon: const Icon(Icons.email_outlined, color: _muted),
              filled: true, fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _brand))),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: sending ? null : () async {
              if (emailCtrl.text.isEmpty) return;
              setSt(() => sending = true);
              final coachId = _supabase.auth.currentUser?.id ?? '';
              await ref.read(coachRelServiceProvider).sendInvite(coachId, emailCtrl.text.trim());
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite sent!'), backgroundColor: _brand));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand, foregroundColor: _white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _white, strokeWidth: 2))
              : const Text('Send Invite', style: TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
      )),
    );
  }

  String _goalLabel(String g) => {
    'fat_loss': 'Fat Loss',
    'muscle_building': 'Muscle Building',
    'general_fitness': 'General Fitness',
    'improve_energy': 'Improve Energy',
    'event_prep': 'Event Prep',
  }[g] ?? g;

  Widget _buildLeaderboardTab() {
    final leaderAsync = ref.watch(coachLeaderboardProvider);
    return leaderAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
      error: (e, _) => _EmptyState(icon: Icons.leaderboard_outlined, message: 'Error loading leaderboard', sub: e.toString()),
      data: (entries) {
        if (entries.isEmpty) return _EmptyState(
          icon: Icons.leaderboard_outlined,
          message: 'No scores yet today',
          sub: 'Client scores update as they complete workouts, nutrition, and habits');
        // AI risk: flag clients scoring < 40 today
        final atRisk = entries.where((e) => (e['total_score'] as int? ?? 100) < 40).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (atRisk.isNotEmpty) Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB4AB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFB4AB).withValues(alpha: 0.4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB4AB), size: 16),
                  SizedBox(width: 6),
                  Text('AI Risk Alert', style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                Text('${atRisk.length} client${atRisk.length > 1 ? 's' : ''} scored under 40 pts today. Consider reaching out.',
                  style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 8),
                ...atRisk.map((e) {
                  final p = e['profile'] as Map<String, dynamic>? ?? {};
                  final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                  return Text('• $n — ${e['total_score'] ?? 0} pts', style: const TextStyle(color: _white, fontSize: 12));
                }),
              ]),
            ),
            ...entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final profile = e['profile'] as Map<String, dynamic>? ?? {};
              final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
              final total = e['total_score'] as int? ?? 0;
              final isAtRisk = total < 40;
              final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i+1}';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isAtRisk ? const Color(0xFFFFB4AB).withValues(alpha: 0.05)
                      : i < 3 ? _brand.withValues(alpha: 0.07) : _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isAtRisk ? const Color(0xFFFFB4AB).withValues(alpha: 0.3)
                      : i < 3 ? _brand.withValues(alpha: 0.2) : _border)),
                child: Row(children: [
                  Text(medal, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isEmpty ? 'Client' : name,
                      style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (isAtRisk) const Text('⚠️ Needs attention', style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 11)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$total pts', style: TextStyle(
                      color: isAtRisk ? const Color(0xFFFFB4AB) : i < 3 ? _tertiary : _primary,
                      fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('W:${e['workout_points'] ?? 0} N:${e['nutrition_points'] ?? 0} H:${e['habits_points'] ?? 0}',
                      style: const TextStyle(color: _muted, fontSize: 10)),
                  ]),
                ]),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildCheckinsTab(
    List<Map<String, dynamic>> checkins,
    List<Map<String, dynamic>> clients,
  ) {
    if (checkins.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline,
        message: "No check-ins today",
        sub: "Client check-ins will appear here");
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: checkins.length,
      itemBuilder: (_, i) {
        final c = checkins[i];
        final userId = c['user_id'] as String;
        final client = clients.where((cl) => cl['id'] == userId).firstOrNull;
        final fn = client?['first_name'] ?? ''; final ln = client?['last_name'] ?? ''; final name = '$fn $ln'.trim().isEmpty ? 'Client' : '$fn $ln'.trim();
        final energy = checkinEnergy(c)?.toInt() ?? 0;
        final stress = c['stress_level'] as int? ?? 0;
        final needsAttention = energy <= 2 || stress >= 4;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: needsAttention ? _error.withValues(alpha: 0.4) : _border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: needsAttention
                    ? _error.withValues(alpha: 0.15)
                    : _brand.withValues(alpha: 0.15)),
                alignment: Alignment.center,
                child: Text(name[0].toUpperCase(),
                  style: TextStyle(
                    color: needsAttention ? _error : _brand,
                    fontSize: 15, fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: _white,
                    fontSize: 14, fontWeight: FontWeight.w600)),
                  if (needsAttention)
                    Text("⚠️ Needs coach attention",
                      style: TextStyle(color: _error, fontSize: 11)),
                ])),
              if (c['notes'] != null && (c['notes'] as String).isNotEmpty)
                Icon(Icons.chat_bubble_outline,
                  color: _primary.withValues(alpha: 0.5), size: 16),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _MiniStat("Mood",   "${c['mood'] ?? '-'}/5",          Icons.sentiment_satisfied_outlined, _primary),
              _MiniStat("Energy", "${energy}/5",                     Icons.bolt,     energy <= 2 ? _error : _tertiary),
              _MiniStat("Stress", "${stress}/5",                     Icons.psychology_outlined, stress >= 4 ? _error : _muted),
              _MiniStat("Sleep",  "${checkinSleepHours(c) ?? '-'}h",    Icons.bedtime_outlined,    _primary),
            ]),
            if (c['notes'] != null && (c['notes'] as String).isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border)),
                child: Text('"${c['notes']}"',
                  style: TextStyle(color: _muted.withValues(alpha: 0.7),
                    fontSize: 12, fontStyle: FontStyle.italic))),
            ],
          ]));
      });
  }

  Widget _buildWorkoutsTab(
    List<Map<String, dynamic>> workouts,
    List<Map<String, dynamic>> clients,
  ) {
    if (workouts.isEmpty) {
      return _EmptyState(
        icon: Icons.fitness_center_outlined,
        message: "No workouts this week",
        sub: "Client workouts will appear here");
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: workouts.length,
      itemBuilder: (_, i) {
        final w = workouts[i];
        final userId = w['user_id'] as String;
        final client = clients.where((cl) => cl['id'] == userId).firstOrNull;
        final fn = client?['first_name'] ?? ''; final ln = client?['last_name'] ?? ''; final name = '$fn $ln'.trim().isEmpty ? 'Client' : '$fn $ln'.trim();
        final dt = w['completed_at'] != null
          ? DateTime.parse(w['completed_at']).toLocal()
          : DateTime.now();
        final timeAgo = DateTime.now().difference(dt);
        final timeStr = timeAgo.inHours < 1
          ? "${timeAgo.inMinutes}m ago"
          : timeAgo.inHours < 24
            ? "${timeAgo.inHours}h ago"
            : "${timeAgo.inDays}d ago";

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border)),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(name[0].toUpperCase(),
                style: const TextStyle(color: _brand, fontSize: 16,
                  fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: _white,
                  fontSize: 14, fontWeight: FontWeight.w600)),
                Text(w['workout_title'] ?? 'Workout',
                  style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 12)),
              ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(timeStr,
                style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 11)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.timer_outlined, color: _brand, size: 12),
                const SizedBox(width: 3),
                Text("${w['duration_minutes'] ?? 0}min",
                  style: TextStyle(color: _brand, fontSize: 11,
                    fontWeight: FontWeight.w600)),
              ]),
            ]),
          ]));
      });
  }
}

// ── AI Recommendation Generator ───────────────────────────────────────────────
List<String> _generateCoachRecs(
  List<Map<String, dynamic>> clients,
  List<Map<String, dynamic>> checkins,
  List<Map<String, dynamic>> workouts,
) {
  final recs = <String>[];
  final total = clients.length;
  if (total == 0) return recs;

  final highRisk = clients.where((c) => c['risk_level'] == 'high').length;
  final noProgram = clients.where((c) => c['program_name'] == null && c['coaching_mode'] == 'coached').length;
  final missedCI  = clients.where((c) {
    final uid = c['id'] as String;
    return !checkins.any((ch) => ch['user_id'] == uid);
  }).length;
  final highStress = checkins.where((c) => (c['stress_level'] as num? ?? 0) >= 7).length;
  final lowEnergy  = checkins.where((c) => (checkinEnergy(c) ?? 10) <= 2).length;
  final programRate = clients.where((c) => c['program_name'] != null).length / total * 100;

  if (highRisk > 0) recs.add('$highRisk client${highRisk > 1 ? 's' : ''} are HIGH RISK — review PAR-Q and get medical clearance before programming.');
  if (missedCI > 0) recs.add('$missedCI client${missedCI > 1 ? 's' : ''} have not submitted a check-in — send a follow-up message.');
  if (noProgram > 0) recs.add('$noProgram coached client${noProgram > 1 ? 's' : ''} still unassigned a program — assign one to improve engagement.');
  if (highStress > 1) recs.add('$highStress clients showing high stress this week — consider scheduling a deload or recovery focus.');
  if (lowEnergy > 1) recs.add('$lowEnergy clients reporting low energy — check nutrition targets and sleep habits.');
  if (programRate < 50 && total >= 3) recs.add('Only ${programRate.toStringAsFixed(0)}% of clients have a program assigned — increase to improve compliance scores.');
  if (workouts.isEmpty && total > 0) recs.add('No client workouts logged this week — check in on motivation and adherence.');

  return recs.take(5).toList();
}

// ── Coach Success Metrics ─────────────────────────────────────────────────────
class _CoachSuccessMetrics extends StatelessWidget {
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> checkins;
  final List<Map<String, dynamic>> workouts;
  const _CoachSuccessMetrics({
    required this.clients,
    required this.checkins,
    required this.workouts,
  });

  @override
  Widget build(BuildContext context) {
    final total = clients.length;
    if (total == 0) return const SizedBox.shrink();

    final checkedIn   = checkins.map((c) => c['user_id']).toSet().length;
    final ciRate      = total > 0 ? (checkedIn / total * 100).toStringAsFixed(0) : '0';
    final programmed  = clients.where((c) => c['program_name'] != null).length;
    final progRate    = total > 0 ? (programmed / total * 100).toStringAsFixed(0) : '0';
    final avgEnergy   = checkins.isEmpty ? 0.0
        : checkins.map((c) => checkinEnergy(c)?.toDouble() ?? 0).reduce((a, b) => a + b) / checkins.length;
    final retainedClients = clients.where((c) {
      final created = DateTime.tryParse(c['created_at'] as String? ?? '');
      return created != null && DateTime.now().difference(created).inDays >= 30;
    }).length;
    final retentionRate = total > 0 ? (retainedClients / total * 100).toStringAsFixed(0) : '0';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bar_chart_outlined, color: _brand, size: 13),
          const SizedBox(width: 6),
          const Text('COACH SUCCESS METRICS',
            style: TextStyle(color: _brand, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _MetricCell('Check-In Rate', '$ciRate%',
            int.tryParse(ciRate) != null && int.parse(ciRate) >= 70 ? _tertiary : _error),
          _MetricCell('Program Rate', '$progRate%',
            int.tryParse(progRate) != null && int.parse(progRate) >= 70 ? _tertiary : _error),
          _MetricCell('Avg Energy', avgEnergy.toStringAsFixed(1),
            avgEnergy >= 6 ? _tertiary : avgEnergy >= 3 ? const Color(0xFFFFD060) : _error),
          _MetricCell('Retention', '$retentionRate%',
            int.tryParse(retentionRate) != null && int.parse(retentionRate) >= 80 ? _tertiary : _error),
        ]),
      ]));
  }
}

class _MetricCell extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MetricCell(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: _muted, fontSize: 9,
        fontWeight: FontWeight.w500), textAlign: TextAlign.center),
    ]));
}

// ── Widgets ───────────────────────────────────────────────────────────────────
class _IntelChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _IntelChip(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w500)),
    ]));
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _SummaryChip({required this.icon, required this.label,
    required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.12), _card]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(color: color, fontSize: 18,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 1),
        Text(label, style: TextStyle(color: _muted.withValues(alpha: 0.7),
          fontSize: 9, fontWeight: FontWeight.w600)),
      ])));
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: color, size: 14),
    const SizedBox(height: 3),
    Text(value, style: TextStyle(color: color, fontSize: 13,
      fontWeight: FontWeight.w700)),
    Text(label, style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 9)),
  ]);
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message, sub;
  const _EmptyState({required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: _brand.withValues(alpha: 0.3), size: 48),
      const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: _white, fontSize: 16,
        fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(sub, style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 13)),
    ]));
}

// ── Notifications Sheet ───────────────────────────────────────────────────────
class _NotificationsSheet extends ConsumerWidget {
  final Future<void> Function(String id) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function() onClearAll;
  const _NotificationsSheet({
    required this.onMarkRead, required this.onMarkAllRead,
    required this.onDelete, required this.onClearAll,
  });

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(coachNotificationsProvider).valueOrNull ?? [];
    final unread = notifs.where((n) => n['read'] == false).length;
    final bottom = MediaQuery.of(context).padding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0B16),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A2A50),
              borderRadius: BorderRadius.circular(2))),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Text('Notifications',
                    style: TextStyle(color: _white, fontSize: 20,
                      fontWeight: FontWeight.w700)),
                  if (unread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _error.withValues(alpha: 0.3))),
                      child: Text('$unread new',
                        style: const TextStyle(color: _error, fontSize: 11,
                          fontWeight: FontWeight.w700))),
                  ],
                ]),
                Row(children: [
                  if (unread > 0)
                    GestureDetector(
                      onTap: () async { await onMarkAllRead(); ref.invalidate(coachNotificationsProvider); },
                      child: const Text('Mark all read',
                        style: TextStyle(color: _brand, fontSize: 13,
                          fontWeight: FontWeight.w600))),
                  if (notifs.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () async { await onClearAll(); ref.invalidate(coachNotificationsProvider); },
                      child: const Text('Clear all',
                        style: TextStyle(color: _error, fontSize: 13,
                          fontWeight: FontWeight.w600))),
                  ],
                ]),
              ])),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1A1020), height: 1),

          // List
          Expanded(
            child: notifs.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none, color: _brand.withValues(alpha: 0.3), size: 48),
                  const SizedBox(height: 12),
                  const Text('No notifications yet',
                    style: TextStyle(color: _white, fontSize: 16,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('New client sign-ups will appear here',
                    style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 13)),
                ]))
              : ListView.separated(
                  controller: ctrl,
                  padding: EdgeInsets.fromLTRB(0, 8, 0, bottom + 20),
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) => const Divider(
                    color: Color(0xFF1A1020), height: 1, indent: 72),
                  itemBuilder: (ctx, i) {
                    final n = notifs[i];
                    final isUnread = n['read'] == false;
                    return Dismissible(
                      key: ValueKey(n['id']),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) async {
                        await onDelete(n['id'] as String);
                        ref.invalidate(coachNotificationsProvider);
                      },
                      background: Container(
                        color: _error.withValues(alpha: 0.18),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline, color: _error)),
                      child: GestureDetector(
                      onTap: () async {
                        if (isUnread) { await onMarkRead(n['id'] as String); ref.invalidate(coachNotificationsProvider); }
                      },
                      child: Container(
                        color: isUnread
                          ? _brand.withValues(alpha: 0.04)
                          : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _brand.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: _brand.withValues(alpha: 0.3), width: 1.5)),
                              child: const Icon(Icons.person_add_outlined,
                                color: _brand, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(n['title'] as String? ?? '',
                                      style: TextStyle(
                                        color: _white,
                                        fontSize: 14,
                                        fontWeight: isUnread
                                          ? FontWeight.w700 : FontWeight.w500))),
                                  if (isUnread)
                                    Container(
                                      width: 8, height: 8,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _brand)),
                                ]),
                                const SizedBox(height: 3),
                                Text(n['body'] as String? ?? '',
                                  style: TextStyle(
                                    color: _muted.withValues(alpha: 0.7),
                                    fontSize: 13, height: 1.4)),
                                const SizedBox(height: 4),
                                Text(_timeAgo(n['created_at'] as String?),
                                  style: TextStyle(
                                    color: _muted.withValues(alpha: 0.4),
                                    fontSize: 11)),
                              ])),
                          ]))));
                  })),
        ])));
  }
}
