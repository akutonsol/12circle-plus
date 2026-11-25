import 'dart:async';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../auth/domain/auth_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart';
import '../../coach/presentation/coach_video_response_screen.dart';
import '../../action_items/presentation/assign_action_item_sheet.dart';
import '../../coach_notes/presentation/coach_notes_sheet.dart';
import '../../coach/data/coach_relationship_service.dart';
import '../../coach/domain/package_provider.dart';
import '../../scoring/domain/score_provider.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../../checkins/domain/checkin_columns.dart';
import '../../coach/domain/program_readiness.dart';
import '../../workout/data/program_schedule.dart' show programWeekLabel;
import '../domain/workout_streak.dart';
import '../../workout/domain/workout_day.dart';
import '../domain/still_reading.dart';
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _pri   = Color(0xFFDDB7FF);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);
const _green = Color(0xFF4ADE80);
const _amber = Color(0xFFFFD060);
const _red   = Color(0xFFFFB4AB);

// ── AI summary generator (rule-based from onboarding data) ────────────────────
String _generateAiSummary(Map<String, dynamic> d) {
  final goal    = d['fitness_goal'] as String? ?? '';
  final days    = d['training_days_per_week'] as int? ?? 0;
  final exp     = d['experience_level'] as String? ?? '';
  final sleep   = d['sleep_hours'] as String? ?? '';
  final stress  = (d['stress_level'] as num?)?.toInt() ?? 0;
  final challs  = d['biggest_challenges'] as String? ?? '';
  // EC-04 · nullable. Only `== 'high'` is tested below, so behaviour is unchanged;
  // what changes is that the variable no longer asserts a risk level nobody recorded.
  final risk    = d['risk_level'] as String?;
  final injuries = d['has_injuries'] as bool? ?? false;
  final loc     = d['training_location'] as String? ?? '';

  final goalLabel = {
    'lose_fat': 'Lose Fat', 'build_muscle': 'Build Muscle',
    'improve_health': 'Improve Health', 'performance': 'Athletic Performance',
    'maintain_weight': 'Maintain Weight',
  }[goal] ?? goal;

  final expLabel = {
    'beginner': 'Beginner', 'intermediate': 'Intermediate', 'advanced': 'Advanced'
  }[exp] ?? exp;

  final lines = <String>[];
  if (goalLabel.isNotEmpty) lines.add('Goal: $goalLabel');
  if (days > 0) lines.add('Training Days: $days/week');
  if (expLabel.isNotEmpty) lines.add('Experience: $expLabel');
  if (sleep.isNotEmpty) lines.add('Sleep: $sleep');
  if (stress > 0) lines.add('Stress: $stress/10');
  if (challs.isNotEmpty) lines.add('Challenges: $challs');

  final strategy = <String>[];
  if (exp == 'beginner') strategy.add('Start with foundational movements and short sessions.');
  if (stress >= 7) strategy.add('High stress — prioritise recovery and sleep.');
  if (sleep.contains('5') || sleep.contains('4')) strategy.add('Limited sleep — avoid excessive volume.');
  if (injuries) strategy.add('Active injuries — modify exercises and avoid aggravating movements.');
  if (risk == 'high') strategy.add('HIGH RISK — review PAR-Q before programming.');
  if (loc == 'home') strategy.add('Home-based — recommend bodyweight or minimal-equipment programs.');
  if (goal == 'lose_fat') strategy.add('Focus on calorie deficit + habit building rather than aggressive cutting.');

  final summary = lines.join(' • ');
  final rec = strategy.isEmpty ? 'No specific flags.' : strategy.join(' ');
  return '$summary\n\nCoaching Strategy: $rec';
}

// ── Suggested coach actions ───────────────────────────────────────────────────
List<Map<String, String>> _generateActions(Map<String, dynamic> d) {
  final actions = <Map<String, String>>[];
  final exp = d['experience_level'] as String? ?? '';
  final loc = d['training_location'] as String? ?? '';
  final injuries = d['has_injuries'] as bool? ?? false;
  // EC-04 · nullable, as above.
  final risk = d['risk_level'] as String?;
  final goal = d['fitness_goal'] as String? ?? '';
  final assignment = d['program_assignment'];
  final nutrition = d['nutrition_plan'];

  if (assignment == null) {
    final prog = exp == 'beginner' ? 'Beginner' : (loc == 'home' ? 'Home' : 'Intermediate');
    actions.add({'icon': 'fitness', 'text': 'Assign $prog Program'});
  }
  if (nutrition == null) {
    actions.add({'icon': 'nutrition', 'text': 'Set Nutrition Targets'});
  }
  actions.add({'icon': 'habit', 'text': 'Assign Water Habit'});
  if (injuries) actions.add({'icon': 'warning', 'text': 'Review Injury Details'});
  if (risk == 'high') actions.add({'icon': 'risk', 'text': 'Review High-Risk PAR-Q'});
  if (goal == 'lose_fat') actions.add({'icon': 'nutrition', 'text': 'Adjust Protein Target'});
  actions.add({'icon': 'checkin', 'text': 'Schedule Check-In Call'});
  return actions.take(5).toList();
}

// ── Client Detail Screen ──────────────────────────────────────────────────────
class ClientDetailScreen extends ConsumerStatefulWidget {
  final String clientId;
  final String clientName;
  /// The coach whose list this was opened from. With none known (null) the page
  /// is nobody's: it shows a way back and reads nothing, whoever is signed in.
  final String? owner;
  const ClientDetailScreen({super.key, required this.clientId,
    required this.clientName, required this.owner});

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

/// A SnackBar of the client page's, which takes down itself and no other: the
/// one up is taken down at once, one still queued as soon as it comes up.
class _Said {
  _Said(this.messenger);
  final ScaffoldMessengerState messenger;
  bool up = false, unwanted = false, over = false;

  void close() {
    unwanted = true;
    if (!up || over || !messenger.mounted) return;
    over = true;
    messenger.removeCurrentSnackBar();
  }
}

/// The content of [said]: built when it comes up, and not before.
class _SaidText extends StatefulWidget {
  final _Said said;
  final Widget child;
  const _SaidText(this.said, {required this.child});

  @override
  State<_SaidText> createState() => _SaidTextState();
}

class _SaidTextState extends State<_SaidText> {
  @override
  void initState() {
    super.initState();
    widget.said.up = true;
    if (widget.said.unwanted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.said.close());
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.said.unwanted ? const SizedBox.shrink() : widget.child;
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  /// P0-FL-59f: whose client this page shows. For anyone else (and once they
  /// sign out) it shows nothing and reads nothing; what was typed on it goes
  /// with its content. Back in as the same coach, the page is theirs again.
  late final String? _owner = widget.owner;
  late final OpenClientPages _pages;
  bool _gone = false;

  /// What was said on the page about the client and has not closed yet.
  final _said = <_Said>{};

  /// Says [text], which may be the client's, to this page's coach only: it is
  /// drawn for nobody else, and goes with the page if the page goes first.
  void _say(String text, Duration duration) {
    final said = _Said(ScaffoldMessenger.of(context));
    _said.add(said);
    said.messenger.showSnackBar(SnackBar(
      content: _SaidText(said, child: OwnedText(text, owner: _owner)),
      behavior: SnackBarBehavior.floating, duration: duration))
      .closed.then((_) => _said.remove(said..over = true));
  }

  /// Takes down what this page said and nothing else that is queued. After the
  /// frame: a messenger cannot be changed while the tree is.
  void _unsay() {
    final said = {..._said};
    if (said.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final s in said) {
        s.close();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _pages = ref.read(openClientPagesProvider)..opened(widget.clientId, _owner);
  }

  @override
  void dispose() {
    _pages.closed(widget.clientId, _owner);
    _unsay();
    _tabs.dispose();
    super.dispose();
  }

  /// The page of a coach who left: a way back, and nothing else.
  Widget _goneFor(BuildContext context) {
    if (!_gone) {
      _gone = true;
      _unsay(); // what was said on it ("Marked done: …") goes too
    }
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [_header(context, '')])));
  }

  @override
  Widget build(BuildContext context) {
    // Watched so that a change redraws; the auth client itself decides.
    if (hasAuthClient) ref.watch(currentUserProvider.select((u) => u?.id));
    if (!isSignedIn(_owner)) return _goneFor(context);
    _gone = false;
    final detailAsync = ref.watch(clientDetailProvider(widget.clientId));
    // P0-FL-37: the assessment is read separately, through the logged RPC, and
    // watched HERE so it is read once per page open whichever tab is showing.
    // Its failure fails only the assessment areas, not the page.
    final assessment = ref.watch(clientAssessmentProvider(widget.clientId));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _header(context, widget.clientName),
          _tabBar(),
          Expanded(child: detailAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
            // SEC-PHI-2. This screen's Assessment and PAR-Q tabs render a
            // client's intake record, and the raw exception was printed into
            // it. A PostgREST error carries table and column names, constraint
            // text and — on a unique violation — the conflicting VALUE. The
            // repository's own `Could not load [noun]` pattern says what
            // happened without quoting the database back at the user (F-2/F-16).
            error: (e, _) => const Center(
                child: Text('Could not load this client',
                    style: TextStyle(color: _mut))),
            data: (profileDetail) {
              // The assessment fields join the page's map only when the RPC
              // answered with a row, so every existing reader keeps its key.
              final row = _loadedAssessmentRow(assessment);
              final detail = row == null
                  ? profileDetail
                  : {...profileDetail, ...row};
              final gated = _AssessmentStatePanel.isNeeded(assessment);
              Widget gatePage() => ListView(
                padding: const EdgeInsets.all(16),
                children: [_AssessmentStatePanel(
                    clientId: widget.clientId, assessment: assessment)]);
              return TabBarView(
                controller: _tabs,
                children: [
                  _OverviewTab(detail: detail, clientId: widget.clientId,
                    assessment: assessment, owner: _owner),
                  gated ? gatePage() : _AssessmentTab(detail: detail),
                  gated ? gatePage() : _ParqHealthTab(detail: detail),
                  _ProgressTab(detail: detail, owner: _owner),
                ],
              );
            },
          )),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context, String name) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    decoration: BoxDecoration(
      color: _card,
      border: Border(bottom: BorderSide(color: _brd))),
    child: Row(children: [
      NamedIconButton(
        label: 'Back',
        onTap: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back_ios, color: _wht, size: 20)),
      const SizedBox(width: 12),
      Text(name,
        style: const TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _tabBar() => Container(
    color: _card,
    child: TabBar(
      controller: _tabs,
      labelColor: _brand,
      unselectedLabelColor: _mut,
      indicatorColor: _brand,
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      tabs: const [
        Tab(text: 'Overview'),
        Tab(text: 'Assessment'),
        Tab(text: 'PAR-Q'),
        Tab(text: 'Progress'),
      ],
    ),
  );
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
class _OverviewTab extends ConsumerWidget {
  final Map<String, dynamic> detail;
  final String clientId;
  /// The logged assessment read (P0-FL-37). The risk badge and AI summary are
  /// assessment data, so they follow its state rather than the profile's.
  final AsyncValue<ClientAssessment> assessment;
  /// The coach whose page this is: what is opened from it is theirs.
  final String? owner;
  const _OverviewTab({required this.detail, required this.clientId,
    required this.assessment, required this.owner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score      = detail['today_score'] as Map<String, dynamic>? ?? {};
    final total      = score['total_score'] as int? ?? 0;
    final wt         = detail['weight_kg'] as num?;
    final fitnessGoal= detail['fitness_goal'] as String? ?? '';
    final habitList  = detail['habits'] as List? ?? [];
    final assignment = detail['program_assignment'] as Map<String, dynamic>?;
    final firstName  = detail['first_name'] as String? ?? '';
    final lastName   = detail['last_name']  as String? ?? '';
    final avatarUrl  = detail['avatar_url'] as String?;
    final height     = detail['height_cm'] as num?;
    final gender     = detail['gender'] as String? ?? '';
    final dobStr     = detail['date_of_birth'] as String?;
    final dob        = dobStr != null ? DateTime.tryParse(dobStr) : null;
    final age        = dob != null
        ? (DateTime.now().difference(dob).inDays / 365).floor()
        : null;
    final coachMode  = detail['coaching_mode'] as String? ?? '';
    final startDate  = assignment?['start_date'] as String?;
    // EC-04 · nullable, so _riskBadge can render "NOT ASSESSED" instead of green.
    final riskLevel  = detail['risk_level'] as String?;
    final summary    = _generateAiSummary(detail);
    final actions    = _generateActions(detail);
    // Coaches can only assign work once the client is on a paid plan with them.
    // P0-FL-12: a check that has not answered (still loading, or failed) is
    // NOT "not subscribed" — [paidPlan] is null then, and the lock message is
    // kept for a check that answered no.
    final paidAsync  = ref.watch(clientHasPaidPlanProvider(clientId));
    final bool? paidPlan = answeredPaidPlan(paidAsync);
    final paidCheckFailed = paidPlan == null && paidAsync.hasError && !paidAsync.isLoading;
    // Consecutive failed checks, so a Try again that fails again reads
    // differently from the first failure instead of looking like nothing happened.
    ref.listen<AsyncValue<bool>>(clientHasPaidPlanProvider(clientId), (_, next) {
      if (next.isLoading) return;
      final failures = ref.read(_paidCheckFailuresProvider(clientId).notifier);
      failures.state = next.hasError ? failures.state + 1 : 0;
    });
    final paidFailures = ref.watch(_paidCheckFailuresProvider(clientId));

    final goalLabel = {
      'lose_fat': 'Lose Fat', 'build_muscle': 'Build Muscle',
      'improve_health': 'Improve Health', 'performance': 'Athletic Performance',
      'maintain_weight': 'Maintain Weight', 'fat_loss': 'Fat Loss',
      'muscle_building': 'Muscle Building', 'general_fitness': 'General Fitness',
    }[fitnessGoal] ?? fitnessGoal;

    final modeLabel = {
      'self_guided': 'Self-Guided', 'coached': 'With Coach', 'ai_coach': 'AI Coach'
    }[coachMode] ?? coachMode;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Client Profile Card ──
        _cardBox(child: LayoutBuilder(builder: (context, header) => Row(children: [
          CircleAvatar(
            radius: 32, backgroundColor: _brd,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(firstName.isNotEmpty ? firstName[0] : '?',
                    style: const TextStyle(color: _pri, fontSize: 22, fontWeight: FontWeight.w700))
                : null),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$firstName $lastName'.trim(),
              style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (age != null) _chip('Age: $age', _pri),
              if (gender.isNotEmpty) _chip(gender, _mut),
              if (height != null) _chip('${height}cm', _mut),
              if (wt != null) _chip('${wt.toStringAsFixed(1)}kg', _mut),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              if (goalLabel.isNotEmpty) _chip(goalLabel, _tert),
              if (modeLabel.isNotEmpty) _chip(modeLabel, _brand),
              if (startDate != null)
                _chip('Started ${startDate.split('T')[0]}', _mut),
            ]),
          ])),
          // Risk badge — only from an assessment that ANSWERED. A read still in
          // flight shows nothing yet; a failed one says the risk is unknown,
          // never "not assessed" (a claim about the client) or low risk.
          // A refused read (42501) says the risk is hidden rather than leaving
          // the slot empty (UX-2). The badge takes no flex — the name column
          // keeps all the room the badge does not use — and is capped at 40%
          // of the name+badge room (_badgeSlot), so at large text scales on a
          // narrow screen it wraps (max 2 lines, ellipsis) instead of
          // overflowing or squeezing the name.
          if (assessment.hasError && !assessment.isLoading)
            _badgeSlot(header, const _RiskStateBadge.unknown())
          else if (_assessmentRefused(assessment))
            _badgeSlot(header, const _RiskStateBadge.hidden())
          else if (_assessmentAnswered(assessment))
            _badgeSlot(header, _riskBadge(riskLevel)),
        ]))),
        const SizedBox(height: 12),

        // ── 12 Circle Score + Compliance ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('12 Circle Score', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            _ScoreRing(total: total),
            const SizedBox(width: 16),
            Expanded(child: _ScoreBreakdown(score: score)),
          ]),
          const SizedBox(height: 16),
          const Text('Compliance', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          // P0-FL-52: above 1.5x text the four tiles go two by two — in one
          // row on a narrow phone each was ~45px inside at 2x and its label
          // broke mid-word. Up to 1.5x the single row is unchanged.
          Builder(builder: (context) {
            final workout = _ComplianceCard('Workout', '${score['workout_points'] ?? 0}', 30, Icons.fitness_center_outlined, _tert);
            final nutrition = _ComplianceCard('Nutrition', '${score['nutrition_points'] ?? 0}', 30, Icons.restaurant_outlined, _pri);
            final habits = _ComplianceCard('Habits', '${score['habits_points'] ?? 0}', 20, Icons.task_alt, const Color(0xFFFFB4AB));
            final checkin = _ComplianceCard('Check-In', '${score['checkin_points'] ?? 0}', 10, Icons.calendar_month_outlined, _amber);
            if (MediaQuery.textScalerOf(context).scale(1) > 1.5) {
              return Column(children: [
                Row(children: [workout, const SizedBox(width: 8), nutrition]),
                const SizedBox(height: 8),
                Row(children: [habits, const SizedBox(width: 8), checkin]),
              ]);
            }
            return Row(children: [
              workout,
              const SizedBox(width: 8),
              nutrition,
              const SizedBox(width: 8),
              habits,
              const SizedBox(width: 8),
              checkin,
            ]);
          }),
        ])),
        const SizedBox(height: 12),

        // ── AI Client Summary ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: _brand, size: 16),
            const SizedBox(width: 6),
            // Flexible: at 2x text on a narrow phone the title wraps instead
            // of overflowing (P0-FL-48).
            const Flexible(child: Text('AI Client Summary', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),
          // Built from the assessment. Without one it would read "No specific
          // flags", which is a claim nobody measured.
          if (_AssessmentStatePanel.isNeeded(assessment))
            _AssessmentStatePanel(clientId: clientId, assessment: assessment)
          else
            Text(summary,
              style: const TextStyle(color: _wht, fontSize: 13, height: 1.6)),
        ])),
        const SizedBox(height: 12),

        // ── 12 Circle Score ──
        _ClientScoreCard(clientId: clientId),
        const SizedBox(height: 12),

        // ── Coach Action Center ──
        _CoachActionCenter(actions: actions, clientId: clientId, paidPlan: paidPlan,
          paidCheckFailed: paidCheckFailed,
          riskActionsUnavailable: _assessmentUnavailable(assessment),
          owner: owner),
        const SizedBox(height: 12),

        // ── Assigned Program ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Assigned Program', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (assignment == null)
            const Text('No program assigned yet', style: TextStyle(color: _mut, fontSize: 13))
          else ...[
            Text((assignment['workout_programs'] as Map?)?['name'] as String? ?? 'Program',
              style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            // R2: counted from start_date; current_week is never advanced.
            Text(programWeekLabel(assignment),
              style: const TextStyle(color: _pri, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          _ClientScheduleCard(clientId: clientId),
          const SizedBox(height: 10),
          // ── Coaching services — gated behind a paid plan ──
          if (paidPlan == null && paidAsync.hasError && !paidAsync.isLoading)
            _LoadFailedNotice(
              title: paidFailures > 1
                  ? "Still couldn't check this client's plan."
                  : "Couldn't check this client's plan.",
              error: paidAsync.error!,
              detail: 'Coaching services stay hidden until it loads.',
              retryLabel: "Try again, check this client's plan",
              onRetry: () => ref.invalidate(clientHasPaidPlanProvider(clientId)),
            )
          else if (paidPlan == null)
            const _CheckingNotice(label: "Checking this client's plan…")
          else if (!paidPlan)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _tert.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _tert.withValues(alpha: 0.25))),
              child: Row(children: [
                const Icon(Icons.lock_outline, color: _tert, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Coaching services unlock once this client subscribes to one of your plans.',
                  style: TextStyle(color: _mut, fontSize: 12, height: 1.4))),
              ]),
            )
          else ...[
            _ActionButton(icon: Icons.fitness_center, label: 'Assign / Change Program',
              onTap: () => _showSheet(context, _AssignProgramSheet(clientId: clientId, ref: ref))),
            const SizedBox(height: 8),
            _ActionButton(icon: Icons.restaurant_menu, label: 'Set Nutrition Targets',
              onTap: () => _showSheet(context, _AssignNutritionSheet(clientId: clientId, ref: ref))),
            const SizedBox(height: 8),
            _ActionButton(icon: Icons.task_alt, label: 'Assign Habits',
              onTap: () => _showSheet(context, _AssignHabitsSheet(clientId: clientId, ref: ref))),
            const SizedBox(height: 8),
            _ActionButton(icon: Icons.checklist_rounded, label: 'Assign Action Item',
              onTap: () => showAssignActionItemSheet(context, ref, clientId, owner: owner)),
            const SizedBox(height: 8),
            _ActionButton(icon: Icons.videocam_rounded, label: 'Send Video Response',
              onTap: () {
                if (stoppedFor(owner, 'ClientDetail.videoResponse', 'open video response')) return;
                final name = '$firstName $lastName'.trim();
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => OpenedByAccount(owner: owner,
                    child: CoachVideoResponseScreen(
                      clientId: clientId, clientName: name.isEmpty ? 'Client' : name))));
              }),
          ],
          const SizedBox(height: 8),
          // Internal coach tools — always available.
          _ActionButton(icon: Icons.lock_outline, label: 'Private Notes',
            onTap: () {
              final name = '$firstName $lastName'.trim();
              showCoachNotesSheet(context, ref, clientId, name.isEmpty ? 'Client' : name, owner: owner);
            }),
          const SizedBox(height: 8),
          _ActionButton(icon: Icons.attach_money_rounded, label: 'Set Custom Price',
            onTap: () => _showCustomPriceDialog(context, clientId, owner)),
        ])),
        const SizedBox(height: 12),

        // ── Assigned Habits ──
        if (habitList.isNotEmpty) ...[
          _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Assigned Habits', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...habitList.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(h['emoji'] as String? ?? '⭐', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(h['name'] as String, style: const TextStyle(color: _wht, fontSize: 13))),
                Text('${h['target_value']} ${h['unit']}', style: const TextStyle(color: _mut, fontSize: 11)),
              ]))),
          ])),
          const SizedBox(height: 12),
        ],

        // ── Client Timeline ──
        _ClientTimeline(detail: detail),
      ],
    );
  }

  void _showSheet(BuildContext context, Widget sheet) {
    if (stoppedFor(owner, 'ClientDetail.openSheet', 'open sheet')) return;
    showModalBottomSheet(
      context: context, backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => OpenedByAccount(owner: owner, child: sheet));
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)));

  /// EC-04 · an ABSENT risk level is not the SAFEST risk level.
  ///
  /// This switch used to end in `default: green / LOW RISK`, so a client whose PAR-Q
  /// was never saved — and a client whose profile read simply FAILED, since the
  /// provider returns null for the whole profile on any error — was affirmatively
  /// presented to their coach as low risk. "The read failed" and "this person is low
  /// risk" were the same pixel, and the default pointed the wrong way on a safety
  /// signal.
  ///
  /// `low` is now matched EXPLICITLY, and everything else — null, empty, or a value
  /// this switch does not know — renders "NOT ASSESSED" in the muted colour, visually
  /// distinct from the green of an assessed low. An unrecognised future value is also
  /// safer shown as unassessed than as safe.
  /// The header's risk-badge slot: intrinsic width, at most 40% of the room
  /// the name column and badge share (the row minus the 64dp avatar and its
  /// 16dp gap) — so the name column always keeps at least 60% of it.
  Widget _badgeSlot(BoxConstraints header, Widget badge) => ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: (header.maxWidth - 64 - 16).clamp(0.0, double.infinity) * 0.4),
      child: badge);

  Widget _riskBadge(String? level) {
    final Color color;
    final String label;
    switch (level) {
      case 'high':     color = _red;   label = 'HIGH RISK'; break;
      case 'moderate': color = _amber; label = 'MOD RISK';  break;
      case 'low':      color = _green; label = 'LOW RISK';  break;
      default:         color = _mut;   label = 'NOT ASSESSED'; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)));
  }
}

/// The header badge when the assessment did NOT answer with a risk level
/// (P0-FL-37 UX-2/UX-3). Each looks unlike every assessed state and unlike
/// "NOT ASSESSED" (a claim about the client), and tells a screen reader why.
class _RiskStateBadge extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  final IconData icon;
  final Color color;
  /// Outlined (no fill): a state of the READ, not a risk level.
  final bool outlined;

  /// The read failed: risk is unknown. Amber, outlined, question mark.
  const _RiskStateBadge.unknown()
      : label = 'RISK UNKNOWN',
        semanticsLabel = 'Risk level unknown — assessment could not load',
        icon = Icons.help_outline,
        color = _amber,
        outlined = true;

  /// 42501: not this client's active coach. Muted, with a lock.
  const _RiskStateBadge.hidden()
      : label = 'RISK HIDDEN',
        semanticsLabel = 'Risk level hidden until coaching is active',
        icon = Icons.lock_outline,
        color = _mut,
        outlined = false;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    label: semanticsLabel,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: outlined ? 0.8 : 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800,
            letterSpacing: 0.5))),
      ])));
}

// ── Client Timeline ───────────────────────────────────────────────────────────
class _ClientTimeline extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _ClientTimeline({required this.detail});

  @override
  Widget build(BuildContext context) {
    final events = <Map<String, dynamic>>[];
    final createdAt  = detail['created_at'] as String?;
    final checkins   = detail['weekly_checkins'] as List? ?? [];
    final weights    = detail['weight_logs'] as List? ?? [];
    final assignment = detail['program_assignment'] as Map?;
    final photos     = detail['progress_photos'] as List? ?? [];
    final onboarded  = detail['onboarding_complete'] as bool? ?? false;

    if (createdAt != null) {
      events.add({'date': createdAt, 'label': 'Account Created',
        'icon': 'person', 'color': 'brand'});
    }
    if (onboarded) {
      events.add({'date': createdAt ?? '', 'label': 'Onboarding Completed',
        'icon': 'check', 'color': 'tert'});
    }
    if (assignment != null) {
      final startDate = assignment['start_date'] as String? ?? assignment['created_at'] as String? ?? '';
      final progName  = (assignment['workout_programs'] as Map?)?['name'] as String? ?? 'Program';
      events.add({'date': startDate, 'label': 'Program Assigned: $progName',
        'icon': 'fitness', 'color': 'brand'});
    }
    if (checkins.isNotEmpty) {
      final first = checkins.last;
      events.add({'date': first['week_start_date'] as String? ?? '',
        'label': 'First Check-In Submitted', 'icon': 'checkin', 'color': 'pri'});
    }
    if (weights.isNotEmpty) {
      final first = weights.last;
      events.add({'date': localDayOf(first['logged_at'] as String?),
        'label': 'First Weight Logged: ${first['weight_kg']}kg',
        'icon': 'weight', 'color': 'tert'});
      if (weights.length > 1) {
        final latest = weights.first;
        events.add({'date': localDayOf(latest['logged_at'] as String?),
          'label': 'Latest Weight: ${latest['weight_kg']}kg',
          'icon': 'weight', 'color': 'mut'});
      }
    }
    if (photos.isNotEmpty) {
      events.add({'date': localDayOf(photos.last['logged_at'] as String?),
        'label': 'First Progress Photo', 'icon': 'photo', 'color': 'pri'});
    }
    if (checkins.isNotEmpty) {
      final latest = checkins.first;
      events.add({'date': latest['week_start_date'] as String? ?? '',
        'label': 'Latest Check-In', 'icon': 'checkin', 'color': 'brand'});
    }

    events.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    if (events.isEmpty) return const SizedBox.shrink();

    return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('CLIENT TIMELINE', style: TextStyle(
        color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 14),
      ...events.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final isLast = i == events.length - 1;
        final color = _colorFor(e['color'] as String);
        final icon  = _iconFor(e['icon'] as String);
        final dateStr = (e['date'] as String).length >= 10
            ? (e['date'] as String).substring(0, 10) : e['date'] as String;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.4))),
              child: Icon(icon, color: color, size: 14)),
            if (!isLast)
              Container(width: 1, height: 28, color: _brd),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['label'] as String,
                style: const TextStyle(color: _wht, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(dateStr, style: const TextStyle(color: _mut, fontSize: 11)),
            ]))),
        ]);
      }),
    ]));
  }

  Color _colorFor(String key) => switch (key) {
    'brand' => _brand, 'tert' => _tert, 'pri' => _pri,
    'green' => _green, 'amber' => _amber, 'red' => _red,
    _ => _mut,
  };

  IconData _iconFor(String key) => switch (key) {
    'person'  => Icons.person_outline,
    'check'   => Icons.check_circle_outline,
    'fitness' => Icons.fitness_center_outlined,
    'checkin' => Icons.calendar_month_outlined,
    'weight'  => Icons.monitor_weight_outlined,
    'photo'   => Icons.photo_camera_outlined,
    _ => Icons.circle_outlined,
  };
}

// ── Assessment Tab ─────────────────────────────────────────────────────────────
/// What the Custom Price field says: blank clears the override; a number sets
/// it; anything else is refused.
///
/// A typo was read as blank. `double.tryParse` answers null for "150/mo" or
/// "1,500", null CLEARED the client's price, and the coach was told "Custom
/// price cleared — using your standard rate." Unreadable input now changes
/// nothing and says why.
@visibleForTesting
({double? price, String? error}) parseCustomPrice(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return (price: null, error: null);
  final v = double.tryParse(t);
  if (v == null || v < 0) {
    return (price: null, error: 'Enter the monthly price as a number, like 150.');
  }
  return (price: v, error: null);
}

/// Opens the custom-price dialog without building the whole client screen,
/// whose many providers a dialog test does not need.
@visibleForTesting
void showCustomPriceDialogForTest(BuildContext context, String clientId) =>
    _showCustomPriceDialog(context, clientId, signedInUid());

/// Coach sets a custom monthly price for THIS client (overrides their global
/// rate). Leaving it blank and saving clears the override.
void _showCustomPriceDialog(BuildContext context, String clientId, String? owner) {
  // P0-FL-59f: opened and typed by [owner], saved as them or not at all; the
  // dialog closes when the account changes.
  if (stoppedFor(owner, 'ClientDetail.customPrice', 'open client price')) return;
  final ctrl = TextEditingController();
  // Why the last Save did not happen, shown on the field INSIDE the dialog. A
  // SnackBar went to the page's messenger, under the dialog's scrim, so the
  // coach saw nothing. [saving] disables Save while the write is in flight.
  String? error;
  var saving = false;
  showDialog(
    context: context,
    builder: (dctx) => OpenedByAccount(owner: owner, child: StatefulBuilder(builder: (sctx, setDialogState) => AlertDialog(
      backgroundColor: _card,
      title: const Text('Custom Price', style: TextStyle(color: _wht, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
            'Set a monthly price just for this client. Leave blank to use your standard rate.',
            style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
        const SizedBox(height: 14),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          onChanged: (_) {
            if (error != null) setDialogState(() => error = null);
          },
          style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700),
            suffixText: '/mo',
            suffixStyle: const TextStyle(color: _mut),
            hintText: 'e.g. 150',
            hintStyle: const TextStyle(color: _mut),
            errorText: error,
            errorMaxLines: 3,
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: _mut)),
        ),
        TextButton(
          onPressed: saving ? null : () async {
            if (stoppedFor(owner, 'ClientDetail.customPrice', 'set client price')) {
              ctrl.clear();
              return;
            }
            final parsed = parseCustomPrice(ctrl.text);
            if (parsed.error != null) {
              setDialogState(() => error = parsed.error);
              return;
            }
            final value = parsed.price;
            setDialogState(() {
              saving = true;
              error = null;
            });
            try {
              await CoachRelationshipService().setClientPrice(clientId, value);
            } catch (e, st) {
              reportError('ClientDetail.customPrice', e, st);
              // A write that failed escaped here unhandled, with nothing said.
              // setClientPrice's StateError says what happened (signed out, no
              // relationship with this client — P0-FL-3). A generic failure
              // (e.g. a timeout) may still have committed, so it does not
              // claim nothing changed. Connection wording only for a failure
              // that IS the connection (P0-FL-11): a server answer (a
              // PostgrestException) said "check your connection" too.
              if (!sctx.mounted || !stillSignedIn(owner)) return;
              setDialogState(() {
                saving = false;
                error = e is StateError
                    ? e.message
                    : isNetworkFailure(e)
                        ? "Couldn't save your price — check your connection and try again."
                        : "Couldn't save your price — try again in a moment. "
                            'If it keeps happening, contact support.';
              });
              return;
            }
            if (stoppedFor(owner, 'ClientDetail.customPrice', 'report client price')) return;
            if (!sctx.mounted || !dctx.mounted) return;
            Navigator.pop(dctx);
            ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(
                content: OwnedText(value == null
                    ? 'Custom price cleared — using your standard rate.'
                    : 'Custom price set to \$${value.toStringAsFixed(0)}/mo.',
                    owner: owner)));
          },
          child: saving
              ? Semantics(
                  label: 'Saving',
                  child: const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _pri)))
              : const Text('Save', style: TextStyle(color: _pri, fontWeight: FontWeight.w700)),
        ),
      ],
    ))),
  );
}

/// Coach insight: the client's chosen training days + time (from onboarding,
/// confirmed when they picked a package).
/// What a card says instead of its data when it has none to show yet: '…'
/// while the first read is in flight, [failed] when it could not be read, and
/// null once there is an answer (which may itself be "nothing").
///
/// The schedule and score cards used `valueOrNull`, which is null in all three
/// cases, so a failed read showed "Client hasn't set a schedule yet." and
/// "0 · 0 · Lvl 1 Bronze" as if they were the client's.
@visibleForTesting
String? unreadNote(AsyncValue<Object?> v, {required String failed}) {
  if (v.hasValue) return null;
  if (v.hasError) return failed;
  return '…';
}

class _ClientScheduleCard extends ConsumerWidget {
  final String clientId;
  const _ClientScheduleCard({required this.clientId});

  static const _dayShort = {
    'monday': 'Mon', 'tuesday': 'Tue', 'wednesday': 'Wed', 'thursday': 'Thu',
    'friday': 'Fri', 'saturday': 'Sat', 'sunday': 'Sun',
  };

  static const _dayOrder = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedAsync = ref.watch(clientScheduleProvider(clientId));
    final sched = schedAsync.valueOrNull;
    final unread = unreadNote(schedAsync, failed: "Couldn't load the schedule.");
    final dayKeys = (sched?['days'] as List?)?.map((d) => '$d').toList() ?? [];
    final time = sched?['session_time'] as String?;
    final dayTimes = (sched?['day_times'] as Map?) ?? {};
    // Sort the client's days Mon→Sun for a clean read.
    final sortedKeys = [...dayKeys]..sort((a, b) =>
        _dayOrder.indexOf(a).compareTo(_dayOrder.indexOf(b)));
    return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TRAINING SCHEDULE',
          style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),
      if (unread != null)
        Text(unread, style: const TextStyle(color: _mut, fontSize: 13))
      else if (sched == null)
        const Text('Client hasn’t set a schedule yet.', style: TextStyle(color: _mut, fontSize: 13))
      else ...[
        // Each training day with its own time (falls back to the default time).
        ...sortedKeys.map((k) {
          final t = (dayTimes['$k'] as String?) ?? time ?? '—';
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.event_repeat_rounded, color: _pri, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_dayShort['$k'] ?? '$k',
                  style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600))),
              const Icon(Icons.schedule_rounded, color: _mut, size: 14),
              const SizedBox(width: 4),
              Text(t, style: const TextStyle(color: _mut, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
        if (sortedKeys.isEmpty)
          const Text('—', style: TextStyle(color: _mut, fontSize: 13)),
        const SizedBox(height: 6),
        Text('${dayKeys.length} sessions/week',
            style: const TextStyle(color: _tert, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ]));
  }
}

class _AssessmentTab extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _AssessmentTab({required this.detail});

  @override
  Widget build(BuildContext context) {
    final fitnessGoal  = _str(detail['fitness_goal']);
    final nutritionGoal= _str(detail['nutrition_goal']);
    final timeline     = _str(detail['target_timeline']);
    final sleep        = _str(detail['sleep_hours']);
    final stress       = (detail['stress_level']  as num?)?.toInt() ?? 0;
    final occupation   = _str(detail['occupation']);
    final exp          = _str(detail['experience_level']);
    final coached      = detail['worked_with_coach_before'] as bool? ?? false;
    final days         = (detail['training_days_per_week'] as num?)?.toInt() ?? 0;
    final loc          = _str(detail['training_location']);
    final dietary      = _str(detail['dietary_restrictions']);
    final allergies    = _str(detail['food_allergies']);

    final goalLabel = {
      'lose_fat': 'Lose Fat', 'build_muscle': 'Build Muscle',
      'improve_health': 'Improve Health', 'performance': 'Athletic Performance',
      'maintain_weight': 'Maintain Weight',
    }[fitnessGoal] ?? fitnessGoal;

    final nutritionLabel = {
      'cut': 'Cutting (deficit)', 'bulk': 'Bulking (surplus)',
      'maintain': 'Maintenance', 'flexible': 'Flexible / Intuitive',
    }[nutritionGoal] ?? nutritionGoal;

    final locLabel = {
      'gym': 'Gym', 'home': 'Home', 'outdoor': 'Outdoor', 'mixed': 'Mixed / Both',
    }[loc] ?? loc;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Goals
        _section('GOALS', [
          _row('Primary Goal', goalLabel),
          _row('Nutrition Goal', nutritionLabel),
          _row('Target Timeline', timeline),
        ]),
        const SizedBox(height: 12),

        // Lifestyle
        _section('LIFESTYLE', [
          _row('Sleep', sleep.isNotEmpty ? sleep : '—'),
          _row('Stress Level', stress > 0 ? '$stress / 10' : '—'),
          _row('Occupation', occupation),
        ]),
        const SizedBox(height: 12),

        // Experience
        _section('EXPERIENCE', [
          _row('Level', exp.isEmpty ? '—' : exp[0].toUpperCase() + exp.substring(1)),
          _row('Worked with coach before', coached ? 'Yes' : 'No'),
        ]),
        const SizedBox(height: 12),

        // Training Availability
        _section('TRAINING AVAILABILITY', [
          _row('Days per Week', days > 0 ? '$days days' : '—'),
          _row('Equipment / Location', locLabel),
        ]),
        const SizedBox(height: 12),

        // Nutrition & Dietary
        _section('NUTRITION & DIETARY', [
          _row('Dietary Restrictions', dietary.isEmpty ? 'None' : dietary),
          _row('Food Allergies', allergies.isEmpty ? 'None' : allergies),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) => _cardBox(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),
      ...rows,
    ]));

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 160,
        child: Text(label, style: const TextStyle(color: _mut, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600))),
    ]));

  /// Coerce a dynamic intake value to a display string. Intake fields like
  /// dietary_restrictions / food_allergies come back as JSON arrays, so a
  /// plain `as String?` cast throws — handle List/num/String/null uniformly.
  static String _str(dynamic v) {
    if (v == null) return '—';
    if (v is String) return v.trim().isEmpty ? '—' : v;
    if (v is List) {
      final items = v.where((e) => e != null && '$e'.trim().isNotEmpty).toList();
      return items.isEmpty ? '—' : items.join(', ');
    }
    return '$v';
  }
}

/// Coerce an intake value (String, JSON List, or null) to a comma-joined
/// string, returning '' when empty so existing `.isEmpty ? 'None'` logic holds.
String _intakeJoin(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  if (v is List) {
    return v
        .where((e) => e != null && '$e'.trim().isNotEmpty)
        .map((e) => '$e'.trim())
        .join(', ');
  }
  return '$v';
}

// ── PAR-Q & Health Tab ────────────────────────────────────────────────────────
class _ParqHealthTab extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _ParqHealthTab({required this.detail});

  static const _parqQuestions = {
    1: 'Heart condition diagnosed by a doctor?',
    2: 'Chest pain during physical activity?',
    3: 'Chest pain in the past month (at rest)?',
    4: 'Dizziness or fainting spells?',
    5: 'Bone or joint problem that exercise may worsen?',
    6: 'Currently taking blood pressure/heart medication?',
    7: 'Doctor advised against unsupervised exercise?',
    8: 'Any other medical reason to avoid exercise?',
  };

  @override
  Widget build(BuildContext context) {
    // EC-04 · no `?? 'low'` and no `?? 0`. A missing score rendered as "0 / 8" reads
    // as the safest possible result, which is the same defect as the badge's green
    // default wearing different clothes.
    final riskLevel   = detail['risk_level']         as String?;
    final riskScore   = (detail['risk_score']        as num?)?.toInt();
    final riskFlags   = _intakeJoin(detail['risk_flags']);
    final medical     = _intakeJoin(detail['medical_conditions']);
    final hasInjuries = detail['has_injuries']       as bool? ?? false;
    final injLocs     = _intakeJoin(detail['injury_locations']);
    final injDesc     = _intakeJoin(detail['injury_description']);
    final parqRaw     = detail['parq_answers']       as Map<String, dynamic>? ?? {};
    final parqMap     = <int, bool>{};
    parqRaw.forEach((k, v) {
      final ki = int.tryParse(k);
      if (ki != null) parqMap[ki] = v as bool? ?? false;
    });

    final Color riskColor;
    final String riskLabel;
    switch (riskLevel) {
      case 'high':     riskColor = _red;   riskLabel = 'High Risk';     break;
      case 'moderate': riskColor = _amber; riskLabel = 'Moderate Risk'; break;
      case 'low':      riskColor = _green; riskLabel = 'Low Risk';      break;
      // EC-04 · see _riskBadge. `low` is explicit; absent is its own state.
      default:         riskColor = _mut;   riskLabel = 'Not Assessed';  break;
    }

    final flags = riskFlags.split(',').where((f) => f.trim().isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Risk Level Card
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('RISK LEVEL', style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: riskColor)),
              child: Text(riskLabel.toUpperCase(),
                style: TextStyle(color: riskColor, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
          ]),
          const SizedBox(height: 10),
          Text(riskScore == null
                  // EC-04 · an unassessed PAR-Q has no score. "0 / 8" would be a
                  // measurement, and the most reassuring one available.
                  ? 'Risk Score: not assessed'
                  : 'Risk Score: $riskScore / 8',
              style: const TextStyle(color: _wht, fontSize: 14)),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6,
              children: flags.map((f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _red.withValues(alpha: 0.4))),
                child: Text(f.replaceAll('_', ' '),
                  style: const TextStyle(color: _red, fontSize: 11, fontWeight: FontWeight.w600)))).toList()),
          ],
        ])),
        const SizedBox(height: 12),

        // PAR-Q Answers
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PAR-Q SCREENING', style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 12),
          if (parqMap.isEmpty)
            const Text('Not completed yet', style: TextStyle(color: _mut, fontSize: 13))
          else
            ..._parqQuestions.entries.map((e) {
              final answered = parqMap[e.key];
              if (answered == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: answered ? _red.withValues(alpha: 0.15) : _green.withValues(alpha: 0.1)),
                    child: Icon(
                      answered ? Icons.warning_amber_rounded : Icons.check,
                      color: answered ? _red : _green, size: 14)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.value,
                    style: TextStyle(
                      color: answered ? _wht : _mut, fontSize: 12,
                      fontWeight: answered ? FontWeight.w600 : FontWeight.normal))),
                ]));
            }),
        ])),
        const SizedBox(height: 12),

        // Medical Conditions
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MEDICAL CONDITIONS', style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 10),
          Text(medical.isEmpty ? 'None reported' : medical,
            style: const TextStyle(color: _wht, fontSize: 13)),
        ])),
        const SizedBox(height: 12),

        // Injuries
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('INJURIES & LIMITATIONS', style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const Spacer(),
            if (hasInjuries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
                child: const Text('ACTIVE', style: TextStyle(color: _amber, fontSize: 10, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          if (!hasInjuries)
            const Text('No injuries reported', style: TextStyle(color: _mut, fontSize: 13))
          else ...[
            if (injLocs.isNotEmpty)
              _infoRow('Locations', injLocs),
            if (injDesc.isNotEmpty)
              _infoRow('Description', injDesc),
          ],
        ])),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _mut, fontSize: 11)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(color: _wht, fontSize: 13)),
    ]));
}

// ── Progress Tab ──────────────────────────────────────────────────────────────
class _ProgressTab extends StatelessWidget {
  final Map<String, dynamic> detail;
  /// The coach whose page this is: the photos opened from it are theirs to see.
  final String? owner;
  const _ProgressTab({required this.detail, required this.owner});

  @override
  Widget build(BuildContext context) {
    final weights    = detail['weight_logs'] as List? ?? [];
    final photos     = detail['progress_photos'] as List? ?? [];
    final checkins   = detail['weekly_checkins'] as List? ?? [];
    final workouts   = detail['workout_logs'] as List? ?? [];
    final nutrition  = detail['nutrition_plan'] as Map<String, dynamic>?;
    final goal       = detail['fitness_goal'] as String? ?? '';
    final goalWeight = (detail['weight_goal_kg'] as num?)?.toDouble();

    // ── Workout Intelligence ──
    final totalWorkouts = workouts.length;
    String lastWorkoutStr = 'None';
    int streak = 0;
    double avgPerWeek = 0;
    if (workouts.isNotEmpty) {
      // The local day, as the streak below counts it — not the UTC date.
      lastWorkoutStr = localWorkoutDate(workouts.first['completed_at'] as String? ?? '');
      // D7: consecutive workout days that reach today or yesterday.
      streak = currentWorkoutStreak(workouts.map((w) => w['completed_at'] as String?));
      final oldest = workouts.last;
      final oldestDate = DateTime.tryParse(oldest['completed_at'] as String? ?? '');
      if (oldestDate != null) {
        final weeks = DateTime.now().difference(oldestDate).inDays / 7;
        avgPerWeek = weeks > 0 ? totalWorkouts / weeks : totalWorkouts.toDouble();
      }
    }

    // ── Check-In Intelligence ──
    double avgEnergy = 0, avgStress = 0, avgMood = 0;
    String energyTrend = '—', stressTrend = '—';
    final allCheckins = List<Map<String, dynamic>>.from(checkins);
    if (allCheckins.isNotEmpty) {
      avgEnergy = allCheckins.map((c) => checkinEnergy(c)?.toDouble() ?? 0).reduce((a, b) => a + b) / allCheckins.length;
      avgStress = allCheckins.map((c) => (c['stress_level'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / allCheckins.length;
      avgMood   = allCheckins.map((c) => (c['mood'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / allCheckins.length;
    }
    if (allCheckins.length >= 2) {
      final e1 = checkinEnergy(allCheckins.first)?.toDouble() ?? 0;
      final e2 = checkinEnergy(allCheckins.last)?.toDouble() ?? 0;
      energyTrend = e1 > e2 ? '↑ Improving' : e1 < e2 ? '↓ Declining' : '→ Stable';
      final s1 = (allCheckins.first['stress_level'] as num?)?.toDouble() ?? 0;
      final s2 = (allCheckins.last['stress_level'] as num?)?.toDouble() ?? 0;
      stressTrend = s1 < s2 ? '↑ Improving' : s1 > s2 ? '↓ Worsening' : '→ Stable';
    }
    // On the check-in's own 1–5 scale (see checkin_columns.dart).
    final checkInInsights = checkinInsights(
        count: allCheckins.length, avgEnergy: avgEnergy,
        avgStress: avgStress, avgMood: avgMood);

    // ── Nutrition Intelligence ──
    double? weightDelta;
    String weightDirection = '—';
    if (weights.length >= 2) {
      final latest  = (weights.first['weight_kg'] as num?)?.toDouble() ?? 0;
      final earlier = (weights.last['weight_kg'] as num?)?.toDouble() ?? 0;
      weightDelta = latest - earlier;
      if (goal == 'lose_fat') {
        weightDirection = weightDelta < 0 ? '↓ On track' : weightDelta > 0 ? '↑ Gaining — adjust' : '→ Stalled';
      } else if (goal == 'build_muscle') {
        weightDirection = weightDelta > 0 ? '↑ On track' : weightDelta < 0 ? '↓ Losing — adjust' : '→ Stalled';
      } else {
        weightDirection = weightDelta < 0 ? '↓ Losing' : weightDelta > 0 ? '↑ Gaining' : '→ Stable';
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Workout Intelligence ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fitness_center_outlined, color: _tert, size: 14),
            const SizedBox(width: 6),
            const Text('WORKOUT INTELLIGENCE', style: TextStyle(
              color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _IntelStat('Total Logged', '$totalWorkouts', _tert),
            _IntelStat('Current Streak', '${streak}d', _brand),
            _IntelStat('Avg / Week', '${avgPerWeek.toStringAsFixed(1)}', _pri),
          ]),
          const SizedBox(height: 10),
          _statRow('Last Workout', lastWorkoutStr),
          if (workouts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('RECENT SESSIONS', style: TextStyle(color: _mut, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            ...workouts.take(4).map((w) {
              final dateStr = localWorkoutDate(w['completed_at'] as String? ?? '');
              // A `workout_sessions` row (`clientDetailProvider` selects its title and
              // seconds), not a name and minutes. A session that recorded no duration
              // shows none, rather than a "0m" nobody measured.
              final name = w['workout_title'] as String? ?? 'Workout';
              final secs = w['duration_seconds'];
              final dur  = secs is num && secs >= 30 ? (secs / 60).round() : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _tert)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name,
                    style: const TextStyle(color: _wht, fontSize: 12))),
                  if (dur != null)
                    Text('${dur}m', style: const TextStyle(color: _mut, fontSize: 11)),
                  const SizedBox(width: 8),
                  Text(dateStr, style: const TextStyle(color: _mut, fontSize: 10)),
                ]));
            }),
          ] else
            const Text('No workout sessions logged yet',
              style: TextStyle(color: _mut, fontSize: 13)),
        ])),
        const SizedBox(height: 12),

        // ── Nutrition Intelligence ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.restaurant_outlined, color: _pri, size: 14),
            const SizedBox(width: 6),
            const Text('NUTRITION INTELLIGENCE', style: TextStyle(
              color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
          const SizedBox(height: 12),
          if (nutrition != null) ...[
            Row(children: [
              _IntelStat('Calories', '${nutrition['calories_target'] ?? '—'}', _pri),
              _IntelStat('Protein', '${nutrition['protein_g'] ?? '—'}g', _tert),
              _IntelStat('Carbs', '${nutrition['carbs_g'] ?? '—'}g', _amber),
            ]),
            const SizedBox(height: 10),
            if (nutrition['fat_g'] != null)
              _statRow('Fat Target', '${nutrition['fat_g']}g'),
            if ((nutrition['notes'] as String?)?.isNotEmpty ?? false)
              _statRow('Notes', nutrition['notes'] as String),
          ] else
            const Text('No nutrition plan assigned yet',
              style: TextStyle(color: _mut, fontSize: 13)),
          const SizedBox(height: 10),
          const Divider(color: _brd, height: 1),
          const SizedBox(height: 10),
          const Text('WEIGHT TREND', style: TextStyle(
            color: _mut, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          if (weights.isEmpty)
            const Text('No weight data yet', style: TextStyle(color: _mut, fontSize: 13))
          else ...[
            _statRow('Direction', weightDirection),
            if (weightDelta != null)
              _statRow('Total Change',
                '${weightDelta >= 0 ? '+' : ''}${weightDelta.toStringAsFixed(1)} kg'),
            if (goalWeight != null)
              _statRow('Goal Weight', '${goalWeight.toStringAsFixed(1)} kg'),
            const SizedBox(height: 8),
            ...weights.take(5).map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _pri)),
                const SizedBox(width: 8),
                Text('${w['weight_kg']} kg',
                  style: const TextStyle(color: _wht, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(localDayOf(w['logged_at'] as String?),
                  style: const TextStyle(color: _mut, fontSize: 11)),
              ]))),
          ],
        ])),
        const SizedBox(height: 12),

        // ── Weekly Check-In Intelligence ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.insights_outlined, color: _brand, size: 14),
            const SizedBox(width: 6),
            const Text('CHECK-IN INTELLIGENCE', style: TextStyle(
              color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
          const SizedBox(height: 12),
          if (allCheckins.isEmpty)
            const Text('No check-ins submitted yet',
              style: TextStyle(color: _mut, fontSize: 13))
          else ...[
            Row(children: [
              _IntelStat('Avg Energy', avgEnergy.toStringAsFixed(1), _tert),
              _IntelStat('Avg Stress', avgStress.toStringAsFixed(1),
                isHighStress(avgStress) ? _red : avgStress >= 3 ? _amber : _green),
              _IntelStat('Avg Mood', avgMood.toStringAsFixed(1), _pri),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _TrendChip('Energy Trend', energyTrend),
              const SizedBox(width: 10),
              _TrendChip('Stress Trend', stressTrend),
            ]),
            const SizedBox(height: 10),
            const Text('INSIGHTS', style: TextStyle(
              color: _mut, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            ...checkInInsights.map((insight) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(insight,
                style: TextStyle(
                  color: insight.startsWith('⚠') ? _amber : _tert,
                  fontSize: 12, fontWeight: FontWeight.w500)))),
            const SizedBox(height: 10),
            const Divider(color: _brd, height: 1),
            const SizedBox(height: 10),
            const Text('RECENT CHECK-INS', style: TextStyle(
              color: _mut, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            ...allCheckins.take(4).map((c) {
              final dateStr = (c['week_start_date'] as String? ?? c['submitted_at'] as String? ?? '').split('T')[0];
              final energy  = checkinEnergy(c)?.toInt();
              final stress  = c['stress_level'] as int?;
              final mood    = c['mood'] as int?;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Text(dateStr, style: const TextStyle(color: _mut, fontSize: 11)),
                  const Spacer(),
                  if (mood != null) ...[
                    Icon(Icons.sentiment_satisfied_outlined, color: _pri, size: 12),
                    Text(' $mood', style: const TextStyle(color: _mut, fontSize: 11)),
                    const SizedBox(width: 8),
                  ],
                  Icon(Icons.bolt, color: _tert, size: 12),
                  Text(' ${energy ?? '—'}', style: const TextStyle(color: _mut, fontSize: 11)),
                  const SizedBox(width: 8),
                  Icon(Icons.psychology_outlined, color: _red, size: 12),
                  Text(' ${stress ?? '—'}', style: const TextStyle(color: _mut, fontSize: 11)),
                ]));
            }),
          ],
        ])),
        const SizedBox(height: 12),

        // ── Starting (onboarding) Photos — the client's Day 1 baseline ──
        Builder(builder: (context) {
          final baseline = detail['onboarding_photos'] as Map? ?? {};
          final entries = [
            ('front', 'Front', baseline['front'] as String?),
            ('side',  'Side',  baseline['side']  as String?),
            ('back',  'Back',  baseline['back']  as String?),
          ].where((e) => e.$3 != null && e.$3!.isNotEmpty).toList();
          if (entries.isEmpty) return const SizedBox.shrink();
          return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('STARTING PHOTOS · BASELINE',
              style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text('Captured during onboarding — the client\'s Day 1.',
              style: TextStyle(color: _mut, fontSize: 11)),
            const SizedBox(height: 10),
            Row(children: [
              for (final e in entries) ...[
                Expanded(child: Column(children: [
                  GestureDetector(
                    onTap: () => _showPhoto(context, e.$3!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(aspectRatio: 3 / 4,
                        child: Image.network(e.$3!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: _brd))))),
                  const SizedBox(height: 4),
                  Text(e.$2, style: const TextStyle(color: _mut, fontSize: 11)),
                ])),
                if (e != entries.last) const SizedBox(width: 8),
              ],
            ]),
          ]));
        }),
        const SizedBox(height: 12),

        // ── Progress Photos (gallery) ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PROGRESS PHOTOS (${photos.length})',
            style: const TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 10),
          if (photos.isEmpty)
            const Text('No photos uploaded yet', style: TextStyle(color: _mut, fontSize: 13))
          else GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: photos.length,
            itemBuilder: (_, i) {
              final url = photos[i]['url'] as String? ?? '';
              return GestureDetector(
                onTap: url.isEmpty ? null : () => _showPhoto(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: _brd))));
            }),
        ])),
      ],
    );
  }

  /// P0-FL-59f: the client's photo is [owner]'s to look at. It closes when they
  /// leave, and is not drawn at all if they left before its first frame.
  void _showPhoto(BuildContext context, String url) {
    if (stoppedFor(owner, 'ClientDetail.showPhoto', 'show client photo')) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dctx) => OpenedByAccount(owner: owner, child: GestureDetector(
        onTap: () => Navigator.pop(dctx),
        child: Stack(children: [
          Center(child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: _mut, size: 48)))),
          Positioned(top: 40, right: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(dctx),
              child: const Icon(Icons.close, color: _wht, size: 28))),
        ]),
      )),
    );
  }

  Widget _statRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(label, style: const TextStyle(color: _mut, fontSize: 12)),
      const Spacer(),
      Text(value, style: const TextStyle(color: _wht, fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
}

class _IntelStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _IntelStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: _mut, fontSize: 10)),
    ]));
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _cardBox({required Widget child}) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: _card, borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _brd)),
  child: child);

class _ComplianceCard extends StatelessWidget {
  final String label;
  final String pts;
  final int max;
  final IconData icon;
  final Color color;
  const _ComplianceCard(this.label, this.pts, this.max, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    // P0-FL-52: one announced tile — "Workout: 30 of 30" — instead of three
    // fragments ("30", "/30", "Workout").
    child: MergeSemantics(child: Semantics(
      label: '$label: $pts of $max',
      excludeSemantics: true,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(pts, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        Text('/$max', style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 9)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _mut, fontSize: 9)),
      ])))));
}

class _TrendChip extends StatelessWidget {
  final String label;
  final String trend;
  const _TrendChip(this.label, this.trend);

  @override
  Widget build(BuildContext context) {
    final color = trend.contains('↑') ? _green : trend.contains('↓') ? _red : _mut;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _mut, fontSize: 11)),
          const SizedBox(height: 3),
          Text(trend, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        ])));
  }
}

// 12 Circle Score snapshot for the coach (read-only analytics).
class _ClientScoreCard extends ConsumerWidget {
  final String clientId;
  const _ClientScoreCard({required this.clientId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientScoreProvider(clientId));
    final s = async.valueOrNull;
    // Not read yet, or not readable: no figure. `valueOrNull` made both read
    // "0 · 0 · Lvl 1 Bronze" — a client's real score shown as a beginner's.
    final known = unreadNote(async, failed: '') == null;
    final cycle = known ? '${(s?['current_cycle_score'] as num?)?.toInt() ?? 0}' : '—';
    final lifetime = known ? '${(s?['lifetime_score'] as num?)?.toInt() ?? 0}' : '—';
    final level = known ? 'Lvl ${(s?['level'] as num?)?.toInt() ?? 1}' : '—';
    final rank = known ? (s?['rank'] as String? ?? 'Bronze') : 'Level';
    return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('12 CIRCLE SCORE', style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),
      Row(children: [
        _scoreCell(cycle, 'This month', _tert),
        _scoreCell(lifetime, 'Lifetime', _pri),
        _scoreCell(level, rank, _brand),
      ]),
    ]));
  }
  Widget _scoreCell(String value, String label, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(color: _mut, fontSize: 11)),
  ]));
}

// Coach Action Center — generated coaching recommendations the coach can act on.
// Approve runs the real underlying flow (assign program / nutrition / habit /
// action item) and clears the item; Dismiss hides it; Edit adjusts the wording.
class _CoachActionCenter extends ConsumerStatefulWidget {
  final List<Map<String, String>> actions;
  final String clientId;
  /// Null while the paid-plan check has not answered (loading or failed).
  final bool? paidPlan;
  /// The check FAILED (as opposed to still running) — only meaningful while
  /// [paidPlan] is null.
  final bool paidCheckFailed;
  /// P0-FL-37 (SEC S-4): the assessment read failed or was refused, so the
  /// assessment-driven items ("Review Injury Details", "Review High-Risk
  /// PAR-Q") cannot be generated. Said in one neutral line — no action is
  /// invented in their place, and their absence is not "nothing to review".
  final bool riskActionsUnavailable;
  /// The coach whose page this is (P0-FL-59f): nothing is opened, changed or
  /// said from it for anyone else.
  final String? owner;
  const _CoachActionCenter({required this.actions, required this.clientId,
    required this.paidPlan, required this.paidCheckFailed,
    this.riskActionsUnavailable = false, required this.owner});

  @override
  ConsumerState<_CoachActionCenter> createState() => _CoachActionCenterState();
}

class _CoachActionCenterState extends ConsumerState<_CoachActionCenter> {
  final Set<String> _cleared = {};        // approved or dismissed → hidden
  final Map<String, String> _edited = {}; // text overrides

  bool _left(String what) =>
      stoppedFor(widget.owner, 'CoachActionCenter', what);

  /// Said by the page, which outlives this tab.
  void _say(String text, Duration duration) => context
      .findAncestorStateOfType<_ClientDetailScreenState>()
      ?._say(text, duration);

  String _key(Map<String, String> a) => a['text'] ?? '';
  String _text(Map<String, String> a) => _edited[_key(a)] ?? a['text'] ?? '';

  /// Opens an assign sheet and answers whether it SAVED: the sheets pop with
  /// `true` only after their write succeeded; closing one, or a failed save,
  /// answers false.
  Future<bool> _openSheet(Widget sheet) async {
    if (_left('open sheet')) return false;
    final saved = await showModalBottomSheet<bool>(
      context: context, backgroundColor: _card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => OpenedByAccount(owner: widget.owner, child: sheet));
    return saved ?? false;
  }

  /// "Approve" routes to the real action -- and the recommendation is cleared
  /// only when that action was actually done. It used to open the sheet and
  /// clear the item at once: closing the sheet, or a save that failed, still
  /// hid the recommendation for the rest of the visit, and the coach believed
  /// it was handled.
  Future<void> _approve(Map<String, String> a) async {
    if (_left('approve')) return;
    final icon = a['icon'] ?? '';
    final opensService = icon == 'fitness' || icon == 'nutrition' || icon == 'habit' || icon == 'checkin';
    // Services stay locked until the client is on a paid plan with this coach.
    // An unanswered check is not "not subscribed" (P0-FL-12).
    if (opensService && widget.paidPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: OwnedText(widget.paidCheckFailed
            ? "Couldn't check this client's plan. Use Try again in Coaching services."
            : "Still checking this client's plan — try again in a moment.",
            owner: widget.owner),
        behavior: SnackBarBehavior.floating));
      return;
    }
    if (opensService && widget.paidPlan == false) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: OwnedText('Locked — the client must subscribe to one of your plans first.',
            owner: widget.owner),
        behavior: SnackBarBehavior.floating));
      return;
    }
    // Route to the real action so "Approve" actually does the thing.
    final bool done;
    switch (icon) {
      case 'fitness':
        done = await _openSheet(_AssignProgramSheet(clientId: widget.clientId, ref: ref));
        break;
      case 'nutrition':
        done = await _openSheet(_AssignNutritionSheet(clientId: widget.clientId, ref: ref));
        break;
      case 'habit':
        done = await _openSheet(_AssignHabitsSheet(clientId: widget.clientId, ref: ref));
        break;
      case 'checkin':
        done = await showAssignActionItemSheet(context, ref, widget.clientId, owner: widget.owner);
        break;
      default:
        // Nothing to save: acknowledging the recommendation IS the action.
        _say('Marked done: ${_text(a)}', const Duration(seconds: 2));
        done = true;
    }
    if (!mounted || !done || _left('clear an approved item')) return;
    setState(() => _cleared.add(_key(a)));
  }

  void _dismiss(Map<String, String> a) {
    if (_left('dismiss')) return;
    setState(() => _cleared.add(_key(a)));
    _say('Dismissed: ${_text(a)}', const Duration(seconds: 1));
  }

  /// P0-FL-59f: the dialog holds what was recommended about the client. It
  /// closes with its coach, and nothing typed in it is kept for the next one.
  void _edit(Map<String, String> a) {
    if (_left('edit')) return;
    final ctrl = TextEditingController(text: _text(a));
    showDialog(
      context: context,
      builder: (dctx) => OpenedByAccount(owner: widget.owner, child: AlertDialog(
        backgroundColor: _card,
        title: const Text('Edit Action', style: TextStyle(color: _wht, fontSize: 16)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: _wht),
          decoration: InputDecoration(
            hintText: 'Action text…',
            hintStyle: const TextStyle(color: _mut),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _brd)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _brand)))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Cancel', style: TextStyle(color: _mut))),
          TextButton(
            onPressed: () {
              final txt = ctrl.text.trim();
              Navigator.pop(dctx);
              if (txt.isEmpty || !mounted || _left('save an edited item')) return;
              setState(() => _edited[_key(a)] = txt);
            },
            child: const Text('Save', style: TextStyle(color: _brand))),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.actions.where((a) => !_cleared.contains(_key(a))).toList();
    return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        // Expanded (was Text + Spacer): the title wraps at large text instead
        // of pushing Add off the card (P0-FL-48).
        const Expanded(child: Text('Coach Action Center',
          style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600))),
        // Keep the generated items; let the coach add their own (once paid).
        if (widget.paidPlan == true)
          // Screen-reader name starts with the visible "Add" (voice control
          // still matches it) and says what is added (P0-FL-48 N1).
          Semantics(
            button: true,
            label: 'Add action item',
            excludeSemantics: true,
            onTap: () => showAssignActionItemSheet(context, ref, widget.clientId, owner: widget.owner),
            child: TextButton.icon(
              onPressed: () => showAssignActionItemSheet(context, ref, widget.clientId, owner: widget.owner),
              icon: const Icon(Icons.add_rounded, color: _brand, size: 16),
              label: const Text('Add', style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w700)),
              // 44px floor (P0-FL-48); it was shrink-wrapped to the text.
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(44, 44), tapTargetSize: MaterialTapTargetSize.shrinkWrap))),
      ]),
      const SizedBox(height: 10),
      // Not a live region: the assessment's own failure notice on this page
      // already announces the failure; this only explains the gap here.
      if (widget.riskActionsUnavailable)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.info_outline, color: _mut, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text('Assessment not loaded — risk actions unavailable',
              style: TextStyle(color: _mut, fontSize: 12))),
          ])),
      if (visible.isEmpty)
        const Text('All caught up — tap “Add” to assign a custom action item.',
          style: TextStyle(color: _mut, fontSize: 13))
      else ...visible.map((a) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _row(a))),
    ]));
  }

  // P0-FL-48: the item's text and its three actions shared one Row, so at
  // large text (and on a 360dp phone with the test font even at 1x) the
  // buttons pushed the row past the card. The text now has the full width
  // and wraps; the actions sit under it, right-aligned, and wrap if needed.
  Widget _row(Map<String, String> a) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _brand.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _brand.withValues(alpha: 0.15))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_iconFor(a['icon'] ?? ''), color: _brand, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(_text(a),
          style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
      Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
        _miniBtn('Approve', _text(a), _tert, () => _approve(a), bold: true),
        _miniBtn('Edit', _text(a), _pri, () => _edit(a)),
        _miniBtn('Dismiss', _text(a), _mut, () => _dismiss(a)),
      ]),
    ]));

  /// 44px floor (they were shrink-wrapped to ~11px text), and a screen-reader
  /// name that says WHICH item the action is for — every row has its own
  /// Approve / Edit / Dismiss, which were otherwise indistinguishable.
  Widget _miniBtn(String label, String item, Color color, VoidCallback onTap, {bool bold = false}) => Semantics(
    button: true,
    label: '$label: $item',
    excludeSemantics: true,
    onTap: onTap,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(44, 44), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: Text(label, style: TextStyle(fontSize: 11,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400))));

  IconData _iconFor(String key) => switch (key) {
    'fitness'  => Icons.fitness_center,
    'nutrition'=> Icons.restaurant_outlined,
    'habit'    => Icons.task_alt,
    'warning'  => Icons.warning_amber_rounded,
    'risk'     => Icons.health_and_safety_outlined,
    'checkin'  => Icons.calendar_month_outlined,
    _          => Icons.auto_awesome,
  };
}

class _ScoreRing extends StatelessWidget {
  final int total;
  const _ScoreRing({required this.total});
  @override
  Widget build(BuildContext context) {
    final pct = total / 100;
    // P0-FL-48: the readout overflowed the fixed 72dp box at 2x text. The box
    // now grows with the text scale (72dp at 1x, as before; capped at 112 so
    // the breakdown beside it keeps room), and the readout is scaled down
    // only if it still would not fit.
    final d = MediaQuery.textScalerOf(context).scale(72).clamp(72.0, 112.0);
    return SizedBox(
      width: d, height: d,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: pct, strokeWidth: 7,
          backgroundColor: _brd,
          valueColor: AlwaysStoppedAnimation(
            total >= 80 ? _green : total >= 50 ? _pri : _red)),
        FittedBox(fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$total', style: const TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('/100', style: TextStyle(color: _mut, fontSize: 9)),
          ])),
      ]));
  }
}

class _ScoreBreakdown extends StatelessWidget {
  final Map<String, dynamic> score;
  const _ScoreBreakdown({required this.score});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
    _chip('Workout',   score['workout_points']   ?? 0, 30, _tert),
    _chip('Nutrition', score['nutrition_points'] ?? 0, 30, _pri),
    _chip('Habits',    score['habits_points']    ?? 0, 20, const Color(0xFFFFB4AB)),
    _chip('Check-In',  score['checkin_points']   ?? 0, 10, _amber),
  ]);

  Widget _chip(String label, int pts, int max, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text('$label $pts/$max',
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)));
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.2))),
      // Expanded (was Text + Spacer): a long label wraps at large text instead
      // of overflowing the row (P0-FL-48).
      child: Row(children: [
        Icon(icon, color: _brand, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600))),
        const Icon(Icons.arrow_forward_ios, color: _mut, size: 14),
      ])));
}

/// A read this screen needs before it can act failed: say so, say what is
/// held back because of it, and offer Try again (P0-FL-12).
///
/// A live region, so a screen reader announces the failure (and a repeat
/// failure, whose [title] the caller changes) without the coach hunting for it.
class _LoadFailedNotice extends StatelessWidget {
  final String title;
  final Object error;
  final String detail;
  /// What Try again does, for a screen reader ("Try again, load current plan").
  final String retryLabel;
  final VoidCallback onRetry;
  const _LoadFailedNotice({
    required this.title, required this.error, required this.detail,
    required this.retryLabel, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // The Try again button sits right beside this, so the non-network next
    // step is the escalation, not a second "try again".
    final nextStep = isNetworkFailure(error)
        ? 'Check your connection, then try again.'
        : 'If it keeps happening, contact support.';
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.error_outline, color: _red, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(title,
            style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text('$detail $nextStep',
          style: const TextStyle(color: _mut, fontSize: 12, height: 1.4)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onRetry,
            child: Text('Try again',
              semanticsLabel: retryLabel,
              style: const TextStyle(color: _brand, fontWeight: FontWeight.w700)))),
      ])));
  }
}

/// Whether the client is on a paid plan, or null while that is not known.
///
/// P0-FL-59f: the check watches nothing but the signed-in id, so an
/// [AsyncLoading] that holds an answer holds the PREVIOUS coach's. (A retry or
/// refresh by the same coach stays [AsyncData] while it re-reads.)
@visibleForTesting
bool? answeredPaidPlan(AsyncValue<bool> v) =>
    v is! AsyncLoading && v.hasValue && !v.hasError ? v.requireValue : null;

/// The settled assessment answer, or null while it loads or after it failed.
ClientAssessment? _settledAssessment(AsyncValue<ClientAssessment> a) =>
    !a.isLoading && !a.hasError && a.hasValue ? a.requireValue : null;

/// The RPC row to merge into the page's map, only when it actually answered.
Map<String, dynamic>? _loadedAssessmentRow(AsyncValue<ClientAssessment> a) {
  final s = _settledAssessment(a);
  return s != null && s.status == ClientAssessmentStatus.loaded ? s.row : null;
}

/// The assessment read answered about THIS client: a row, or no row at all.
/// (Not while loading, not on failure, not when the coach may not read it.)
bool _assessmentAnswered(AsyncValue<ClientAssessment> a) {
  final s = _settledAssessment(a);
  return s != null && s.status != ClientAssessmentStatus.notActiveCoach;
}

/// The read settled as 42501: the coach may not read it yet.
bool _assessmentRefused(AsyncValue<ClientAssessment> a) =>
    _settledAssessment(a)?.status == ClientAssessmentStatus.notActiveCoach;

/// The read settled WITHOUT the client's answers it would need for risk
/// actions: it failed, or it was refused. (Not while loading; not a client
/// with no assessment — that is an answer, and there is no risk to act on.)
bool _assessmentUnavailable(AsyncValue<ClientAssessment> a) =>
    (a.hasError && !a.isLoading) || _assessmentRefused(a);

/// What the assessment areas show instead of answers they do not have
/// (P0-FL-37). A failed or refused read is never rendered as an empty
/// assessment, because an empty PAR-Q reads as a client with no flags.
class _AssessmentStatePanel extends ConsumerWidget {
  final String clientId;
  final AsyncValue<ClientAssessment> assessment;
  const _AssessmentStatePanel({required this.clientId, required this.assessment});

  /// True when there are no assessment answers to show.
  static bool isNeeded(AsyncValue<ClientAssessment> a) {
    final s = _settledAssessment(a);
    return s == null || !s.hasAssessment;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loading first: a Try again in flight shows this, not a second button,
    // so the read cannot be fired twice.
    if (assessment.isLoading) {
      return const _CheckingNotice(label: "Loading this client's assessment…");
    }
    if (assessment.hasError) {
      return _LoadFailedNotice(
        title: "Couldn't load this client's assessment.",
        error: assessment.error!,
        detail: 'Risk level and PAR-Q answers stay hidden until it loads.',
        retryLabel: "Try again, load this client's assessment",
        onRetry: () => ref.invalidate(clientAssessmentProvider(clientId)),
      );
    }
    final s = assessment.requireValue;
    final String text;
    var icon = Icons.assignment_outlined;
    switch (s.status) {
      case ClientAssessmentStatus.notActiveCoach:
        text = "This client's assessment is available once coaching is active.";
        icon = Icons.lock_outline;
        break;
      case ClientAssessmentStatus.noRow:
        // UX-1: names the cause, so it does not read like "Not completed yet".
        text = 'No assessment on file for this client yet — it appears here '
            'once they complete one.';
        break;
      case ClientAssessmentStatus.loaded:
        // has_assessment = false: the intake was never filled in.
        text = 'Not completed yet — this client has not finished their assessment.';
        break;
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _brd)),
        child: Row(children: [
          Icon(icon, color: _mut, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
            style: const TextStyle(color: _mut, fontSize: 13, height: 1.4))),
        ])));
  }
}

class _CheckingNotice extends StatelessWidget {
  final String label;
  const _CheckingNotice({required this.label});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Row(children: [
      const SizedBox(width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: _brand)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(color: _mut, fontSize: 12))),
    ]));
}

/// Consecutive failed paid-plan checks for one client, so a repeat failure is
/// told apart from the first ("Still couldn't…").
final _paidCheckFailuresProvider =
    StateProvider.autoDispose.family<int, String>((ref, clientId) => 0);

// ── Assign Program Sheet ──────────────────────────────────────────────────────
class _AssignProgramSheet extends ConsumerStatefulWidget {
  final String clientId;
  final WidgetRef ref;
  const _AssignProgramSheet({required this.clientId, required this.ref});
  @override
  ConsumerState<_AssignProgramSheet> createState() => _AssignProgramSheetState();
}

class _AssignProgramSheetState extends ConsumerState<_AssignProgramSheet> {
  String? _selectedProgramId;
  bool _saving = false;

  /// P0-FL-59f: whose sheet this is. Saved as them, or not at all; the sheet
  /// itself closes when they leave ([OpenedByAccount]). Same for the two below.
  final String? _owner = signedInUid();

  @override
  Widget build(BuildContext context) {
    final programsAsync =
        heldFor(_owner, ref.watch(myProgramsProvider));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Assign Workout Program',
          style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        // S1: the list scrolls and the button stays on screen, as in the habits
        // sheet. Laid out in a plain Column, a coach's ordinary library ran past
        // the bottom of a phone and took "Assign Program" with it.
        Flexible(child: SingleChildScrollView(child: programsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
          error: (e, _) => const Text('Could not load programs',
              style: TextStyle(color: _mut)),
          data: (programs) => programs.isEmpty
            ? const Text('No programs yet. Create a program first.',
                style: TextStyle(color: _mut))
            : Column(children: programs.map((p) {
                // A program KNOWN to have no training days cannot be assigned:
                // the client would own a program with nothing in it. See
                // program_readiness.dart for how one comes to exist.
                final empty = isKnownEmptyProgram(p);
                final goal = ((p['goal'] as String?) ?? '').trim();
                return Opacity(opacity: empty ? 0.45 : 1, child: GestureDetector(
                onTap: empty ? null : () => setState(() => _selectedProgramId = p['id'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _selectedProgramId == p['id']
                        ? _brand.withValues(alpha: 0.15) : _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selectedProgramId == p['id'] ? _brand : _brd)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] as String,
                        style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(empty
                          ? 'No training days yet — add workouts in Programs before assigning'
                          : '${p['duration_weeks']} weeks${goal.isEmpty ? '' : ' • $goal'}',
                        style: const TextStyle(color: _mut, fontSize: 12)),
                    ])),
                    if (_selectedProgramId == p['id'])
                      const Icon(Icons.check_circle, color: _brand, size: 20),
                  ]))));
              }).toList()),
        ))),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedProgramId == null || _saving ? null : _assign,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand, foregroundColor: _wht,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: _wht, strokeWidth: 2))
              : const Text('Assign Program',
                  style: TextStyle(fontWeight: FontWeight.w700)))),
      ]));
  }

  Future<void> _assign() async {
    // Read before the await: the coach can dismiss the sheet while the write is in
    // flight, and a disposed State's `ref` throws.
    final container = ProviderScope.containerOf(context);
    if (stoppedFor(_owner, 'AssignProgramSheet._assign', 'assign program')) {
      setState(() => _selectedProgramId = null);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(coachProgramServiceProvider)
          .assignProgram(_selectedProgramId!, widget.clientId);
      if (stoppedFor(_owner, 'AssignProgramSheet._assign', 'report assigned program')) return;
      // The page behind the sheet reads the assignment through these two, and
      // neither refreshes itself: the Assigned Program card kept naming the
      // program this one had just replaced.
      container.invalidate(clientDetailProvider(widget.clientId));
      container.invalidate(clientScheduleProvider(widget.clientId));
    } catch (e, s) {
      // Same defect class as the nutrition save: this had no handler, so a
      // failure left the sheet spinning and the coach told nothing.
      reportError('AssignProgramSheet._assign', e, s);
      if (!mounted || !stillSignedIn(_owner)) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: OwnedText("Couldn't assign the program — check your connection and try again.",
              owner: _owner)));
      return;
    }
    if (mounted) {
      Navigator.pop(context, true); // saved: the Action Center may clear the item
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: OwnedText('Program assigned!', owner: _owner), backgroundColor: _brand));
    }
  }
}

// ── Assign Nutrition Sheet ────────────────────────────────────────────────────
class _AssignNutritionSheet extends ConsumerStatefulWidget {
  final String clientId;
  final WidgetRef ref;
  const _AssignNutritionSheet({required this.clientId, required this.ref});
  @override
  ConsumerState<_AssignNutritionSheet> createState() => _AssignNutritionSheetState();
}

class _AssignNutritionSheetState extends ConsumerState<_AssignNutritionSheet> {
  final _cal  = TextEditingController();
  final _pro  = TextEditingController();
  final _carb = TextEditingController();
  final _fat  = TextEditingController();
  final _water= TextEditingController();
  final _notes= TextEditingController();
  bool _saving = false;
  final String? _owner = signedInUid();
  // P0-FL-12: Save stays off until the current plan has been READ. The prefill
  // had no error handler: a failed read left the form blank, and Save then
  // wrote the coach's blanks over the client's existing plan. A read that
  // answered "no plan" counts as loaded.
  // The fields are read-only until then too: a coach typing into a form that a
  // later successful Try again then pre-fills would have their edits silently
  // overwritten (or, unnoticed, mixed with the server's).
  bool _loaded = false;
  Object? _loadError;
  int _loadFailures = 0; // consecutive — a repeat failure reads "Still couldn't…"

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  /// Pre-fill with the client's current active plan so the coach can review/edit.
  Future<void> _loadCurrentPlan() async {
    if (_loadError != null) setState(() => _loadError = null);
    final Map<String, dynamic>? p;
    try {
      p = await ref.read(coachProgramServiceProvider).getClientNutritionPlan(widget.clientId);
    } catch (e, s) {
      reportError('AssignNutritionSheet._loadCurrentPlan', e, s);
      if (mounted && stillSignedIn(_owner)) {
        setState(() {
          _loadError = e;
          _loadFailures++;
        });
      }
      return;
    }
    if (!mounted || !stillSignedIn(_owner)) return;
    setState(() {
      _loaded = true;
      _loadFailures = 0;
      if (p == null) return;
      _cal.text   = '${p['calories_target'] ?? ''}';
      _pro.text   = '${p['protein_g'] ?? ''}';
      _carb.text  = '${p['carbs_g'] ?? ''}';
      _fat.text   = '${p['fat_g'] ?? ''}';
      _water.text = p['water_target_oz'] == null ? '' : '${p['water_target_oz']}';
      _notes.text = '${p['notes'] ?? ''}';
    });
  }

  @override
  void dispose() {
    _cal.dispose(); _pro.dispose(); _carb.dispose();
    _fat.dispose(); _water.dispose(); _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Set Nutrition Targets',
        style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      if (_loadError != null) ...[
        _LoadFailedNotice(
          title: _loadFailures > 1
              ? "Still couldn't load the current nutrition plan."
              : "Couldn't load the current nutrition plan.",
          error: _loadError!,
          detail: "You can't save until it loads, so this client's plan isn't overwritten.",
          retryLabel: 'Try again, load current plan',
          onRetry: _loadCurrentPlan,
        ),
        const SizedBox(height: 16),
      ] else if (!_loaded) ...[
        const _CheckingNotice(label: 'Loading the current plan…'),
        const SizedBox(height: 16),
      ],
      Row(children: [
        Expanded(child: _field(_cal, 'Calories', '1850')),
        const SizedBox(width: 12),
        Expanded(child: _field(_pro, 'Protein (g)', '140')),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _field(_carb, 'Carbs (g)', '170')),
        const SizedBox(width: 12),
        Expanded(child: _field(_fat, 'Fat (g)', '60')),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _field(_water, 'Water (oz)', '64')),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox()),
      ]),
      const SizedBox(height: 12),
      _field(_notes, 'Notes (optional)', 'Eat whole foods, avoid processed...'),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _saving || !_loaded ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand, foregroundColor: _wht,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _saving
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: _wht, strokeWidth: 2))
            : const Text('Save Nutrition Plan',
                style: TextStyle(fontWeight: FontWeight.w700)))),
    ]));

  Widget _field(TextEditingController c, String label, String hint) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _mut, fontSize: 12)),
      const SizedBox(height: 4),
      TextField(
        controller: c,
        enabled: _loaded,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: _wht),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: _mut),
          filled: true, fillColor: _bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _brd)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _brd)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _brand)))),
    ]);

  /// `assign_nutrition_plan` raises SQLSTATE 42501 for every refusal (migration 184).
  static bool _isNotAuthorized(Object e) =>
      e is PostgrestException && e.code == '42501';

  Future<void> _save() async {
    // Never write a form that was not filled from the server (P0-FL-12).
    if (!_loaded) return;
    final cal  = int.tryParse(_cal.text);
    final pro  = int.tryParse(_pro.text);
    final carb = int.tryParse(_carb.text);
    final fat  = int.tryParse(_fat.text);
    if (cal == null || pro == null || carb == null || fat == null) return;
    if (stoppedFor(_owner, 'AssignNutritionSheet._save', 'save nutrition plan')) {
      for (final c in [_cal, _pro, _carb, _fat, _water, _notes]) { c.clear(); }
      setState(() => _loaded = false);
      return;
    }
    // Read before the await: the sheet can be dismissed while the write is in flight,
    // and a disposed State's `ref` throws.
    final container = ProviderScope.containerOf(context);
    setState(() => _saving = true);
    try {
      await ref.read(coachProgramServiceProvider).assignNutritionPlan(
        widget.clientId,
        calories: cal, protein: pro, carbs: carb, fat: fat,
        waterOz: int.tryParse(_water.text),
        notes: _notes.text.isEmpty ? null : _notes.text);
      if (stoppedFor(_owner, 'AssignNutritionSheet._save', 'report saved plan')) return;
      // The page behind the sheet reads the plan through this and does not refresh
      // itself: it kept saying "No nutrition plan assigned yet".
      container.invalidate(clientDetailProvider(widget.clientId));
    } catch (e, s) {
      // This used to have no handler: a failed save left the sheet spinning and the
      // coach told nothing. Since migration 184 the RPC also refuses (42501) when
      // the relationship is no longer active, e.g. the client cancelled while this
      // sheet was open — that case gets its own plain sentence.
      reportError('AssignNutritionSheet._save', e, s);
      if (!mounted || !stillSignedIn(_owner)) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: OwnedText(
          _isNotAuthorized(e)
              ? "This client isn't active with you any more, so the plan wasn't saved."
              : isNetworkFailure(e)
                  ? "Couldn't save the plan — check your connection and try again."
                  : "Couldn't save the plan. Try again, and if it keeps happening, "
                      'contact support.', owner: _owner)));
      return;
    }
    if (mounted) {
      Navigator.pop(context, true); // saved: the Action Center may clear the item
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: OwnedText('Nutrition plan saved!', owner: _owner), backgroundColor: _brand));
    }
  }
}

// ── Assign Habits Sheet ───────────────────────────────────────────────────────
class _AssignHabitsSheet extends ConsumerStatefulWidget {
  final String clientId;
  final WidgetRef ref;
  const _AssignHabitsSheet({required this.clientId, required this.ref});
  @override
  ConsumerState<_AssignHabitsSheet> createState() => _AssignHabitsSheetState();
}

class _AssignHabitsSheetState extends ConsumerState<_AssignHabitsSheet> {
  // hasValue → coach fills in a number (the "___" blanks); else it's a yes/do-it habit.
  static const _presets = [
    {'name': 'Water Intake', 'emoji': '💧', 'unit': 'oz',      'category': 'health',      'value': true,  'default': 64,  'tpl': 'Drink ___ oz Water'},
    {'name': 'Steps',        'emoji': '👟', 'unit': 'steps',   'category': 'fitness',     'value': true,  'default': 10000, 'tpl': 'Hit ___ Steps'},
    {'name': 'Log Meals Daily', 'emoji': '🍽️', 'unit': '',    'category': 'nutrition',   'value': false, 'default': 1,   'tpl': 'Log Meals Daily'},
    {'name': 'Sleep',        'emoji': '😴', 'unit': 'hours',   'category': 'sleep',       'value': true,  'default': 8,   'tpl': 'Sleep ___ Hours'},
    {'name': 'Meditation',   'emoji': '🧘', 'unit': 'minutes', 'category': 'mindfulness', 'value': true,  'default': 10,  'tpl': 'Meditation'},
    {'name': 'Workout',      'emoji': '🏋️', 'unit': 'session', 'category': 'fitness',     'value': false, 'default': 1,   'tpl': 'Workout'},
    {'name': 'Mobility',     'emoji': '🤸', 'unit': 'minutes', 'category': 'recovery',    'value': true,  'default': 10,  'tpl': 'Mobility'},
    {'name': 'Supplements',  'emoji': '💊', 'unit': 'serving', 'category': 'nutrition',   'value': false, 'default': 1,   'tpl': 'Supplements'},
    {'name': 'Protein Goal', 'emoji': '🥩', 'unit': 'grams',   'category': 'nutrition',   'value': true,  'default': 140, 'tpl': 'Protein goal ___'},
    {'name': 'Complete Assigned Workouts', 'emoji': '✅', 'unit': '', 'category': 'fitness', 'value': false, 'default': 1, 'tpl': 'Complete Assigned Workouts'},
  ];

  final Set<int> _selected = {};
  final Map<int, TextEditingController> _vals = {};
  bool _saving = false;
  final String? _owner = signedInUid();
  // P0-FL-12: assignHabits switches OFF every active habit before inserting the
  // selection, so a selection that was never pre-filled (failed read, no error
  // handler) wiped the client's habits on Save. Save stays off until the read
  // succeeded; a read that answered "no habits" counts as loaded.
  // The toggles and targets are locked until then too, so a successful Try
  // again can never merge the server's habits into picks the coach made blind.
  bool _loaded = false;
  Object? _loadError;
  int _loadFailures = 0; // consecutive — a repeat failure reads "Still couldn't…"

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _presets.length; i++) {
      _vals[i] = TextEditingController(text: '${_presets[i]['default']}');
    }
    _loadCurrentHabits();
  }

  /// Pre-select habits already assigned + restore their values.
  Future<void> _loadCurrentHabits() async {
    if (_loadError != null) setState(() => _loadError = null);
    final List<Map<String, dynamic>> rows;
    try {
      rows = await ref.read(coachProgramServiceProvider).getClientHabits(widget.clientId);
    } catch (e, s) {
      reportError('AssignHabitsSheet._loadCurrentHabits', e, s);
      if (mounted && stillSignedIn(_owner)) {
        setState(() {
          _loadError = e;
          _loadFailures++;
        });
      }
      return;
    }
    if (!mounted || !stillSignedIn(_owner)) return;
    setState(() {
      _loaded = true;
      _loadFailures = 0;
      for (final r in rows) {
        final idx = _presets.indexWhere((p) => p['name'] == r['name']);
        if (idx >= 0) {
          _selected.add(idx);
          if (r['target_value'] != null) _vals[idx]!.text = '${r['target_value']}';
        }
      }
    });
  }

  @override
  void dispose() {
    for (final c in _vals.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Assign Habits',
        style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Tap to assign. For ones with a blank, set the daily target.',
        style: TextStyle(color: _mut, fontSize: 13)),
      const SizedBox(height: 14),
      if (_loadError != null) ...[
        _LoadFailedNotice(
          title: _loadFailures > 1
              ? "Still couldn't load the current habits."
              : "Couldn't load the current habits.",
          error: _loadError!,
          detail: "You can't save until they load, so this client's habits aren't switched off.",
          retryLabel: 'Try again, load current habits',
          onRetry: _loadCurrentHabits,
        ),
        const SizedBox(height: 14),
      ] else if (!_loaded) ...[
        const _CheckingNotice(label: 'Loading the current habits…'),
        const SizedBox(height: 14),
      ],
      Flexible(child: ListView.separated(
        shrinkWrap: true,
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p   = _presets[i];
          final sel = _selected.contains(i);
          final hasValue = p['value'] == true;
          return GestureDetector(
            onTap: _loaded
                ? () => setState(() => sel ? _selected.remove(i) : _selected.add(i))
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? _brand.withValues(alpha: 0.15) : _bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? _brand : _brd)),
              child: Row(children: [
                Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: sel ? _brand : _mut, size: 18),
                const SizedBox(width: 10),
                Text(p['emoji'] as String, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(p['name'] as String,
                  style: TextStyle(color: sel ? _wht : _mut, fontSize: 13, fontWeight: FontWeight.w600))),
                if (sel && hasValue) ...[
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _vals[i],
                      enabled: _loaded,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _wht, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        filled: true, fillColor: _bg,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _brand)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _brand))))),
                  const SizedBox(width: 6),
                  SizedBox(width: 46, child: Text(p['unit'] as String,
                    style: const TextStyle(color: _mut, fontSize: 11))),
                ],
              ])));
        })),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _selected.isEmpty || _saving || !_loaded ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand, foregroundColor: _wht,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _saving
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: _wht, strokeWidth: 2))
            : Text('Assign ${_selected.length} Habit${_selected.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700)))),
    ]));

  Future<void> _save() async {
    // Never send a selection that was not pre-filled from the server (P0-FL-12).
    if (!_loaded) return;
    if (stoppedFor(_owner, 'AssignHabitsSheet._save', 'assign habits')) {
      setState(() {
        _selected.clear();
        _loaded = false;
      });
      return;
    }
    // Read before the await, as in the nutrition sheet.
    final container = ProviderScope.containerOf(context);
    setState(() => _saving = true);
    final habits = _selected.map((i) {
      final p = _presets[i];
      final v = p['value'] == true ? int.tryParse(_vals[i]!.text) : null;
      return {
        'name': p['name'], 'emoji': p['emoji'], 'unit': p['unit'], 'category': p['category'],
        'target_value': v ?? (p['default'] as int),
      };
    }).toList();
    try {
      await ref.read(coachProgramServiceProvider).assignHabits(widget.clientId, habits);
      if (stoppedFor(_owner, 'AssignHabitsSheet._save', 'report assigned habits')) return;
      // The page lists the client's habits from this and does not refresh itself.
      container.invalidate(clientDetailProvider(widget.clientId));
    } catch (e, s) {
      reportError('AssignHabitsSheet._save', e, s);
      if (!mounted || !stillSignedIn(_owner)) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: OwnedText(
          isNetworkFailure(e)
              ? "Couldn't assign habits — check your connection and try again."
              : "Couldn't assign habits. Try again, and if it keeps happening, "
                  'contact support.', owner: _owner)));
      return;
    }
    if (mounted) {
      Navigator.pop(context, true); // saved: the Action Center may clear the item
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: OwnedText('Habits assigned!', owner: _owner), backgroundColor: _brand));
    }
  }
}

/// `yyyy-mm-dd` of a stored instant in the viewer's own zone, or '' when absent.
///
/// The timeline and the weigh-in list took the first ten characters of the
/// stored string, which is the UTC date: a client's 21:00 weigh-in in New York
/// was listed under the next day. A date-only value (`week_start_date`) has no
/// time and is returned as it is.
@visibleForTesting
String localDayOf(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  if (iso.length <= 10) return iso;
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
