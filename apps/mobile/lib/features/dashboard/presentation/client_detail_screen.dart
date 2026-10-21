import '../../../core/observability/app_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../coach/domain/coach_ecosystem_provider.dart';
import '../../coach/presentation/coach_video_response_screen.dart';
import '../../action_items/presentation/assign_action_item_sheet.dart';
import '../../coach_notes/presentation/coach_notes_sheet.dart';
import '../../coach/data/coach_relationship_service.dart';
import '../../coach/domain/package_provider.dart';
import '../../scoring/domain/score_provider.dart';
import '../../../core/widgets/named_icon_button.dart';

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
  const ClientDetailScreen({super.key, required this.clientId, required this.clientName});

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(clientDetailProvider(widget.clientId));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _header(context),
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
            data: (detail) => TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(detail: detail, clientId: widget.clientId),
                _AssessmentTab(detail: detail),
                _ParqHealthTab(detail: detail),
                _ProgressTab(detail: detail),
              ],
            ),
          )),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
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
      Text(widget.clientName,
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
  const _OverviewTab({required this.detail, required this.clientId});

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
    final paidPlan   = ref.watch(clientHasPaidPlanProvider(clientId)).valueOrNull ?? false;

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
        _cardBox(child: Row(children: [
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
          // Risk badge
          _riskBadge(riskLevel),
        ])),
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
          Row(children: [
            _ComplianceCard('Workout', '${score['workout_points'] ?? 0}', 30, Icons.fitness_center_outlined, _tert),
            const SizedBox(width: 8),
            _ComplianceCard('Nutrition', '${score['nutrition_points'] ?? 0}', 30, Icons.restaurant_outlined, _pri),
            const SizedBox(width: 8),
            _ComplianceCard('Habits', '${score['habits_points'] ?? 0}', 20, Icons.task_alt, const Color(0xFFFFB4AB)),
            const SizedBox(width: 8),
            _ComplianceCard('Check-In', '${score['checkin_points'] ?? 0}', 10, Icons.calendar_month_outlined, _amber),
          ]),
        ])),
        const SizedBox(height: 12),

        // ── AI Client Summary ──
        _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: _brand, size: 16),
            const SizedBox(width: 6),
            const Text('AI Client Summary', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(summary,
            style: const TextStyle(color: _wht, fontSize: 13, height: 1.6)),
        ])),
        const SizedBox(height: 12),

        // ── 12 Circle Score ──
        _ClientScoreCard(clientId: clientId),
        const SizedBox(height: 12),

        // ── Coach Action Center ──
        _CoachActionCenter(actions: actions, clientId: clientId, paidPlan: paidPlan),
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
            Text('Week ${assignment['current_week']} of ${(assignment['workout_programs'] as Map?)?['duration_weeks'] ?? 12}',
              style: const TextStyle(color: _pri, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          _ClientScheduleCard(clientId: clientId),
          const SizedBox(height: 10),
          // ── Coaching services — gated behind a paid plan ──
          if (!paidPlan)
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
              onTap: () => showAssignActionItemSheet(context, ref, clientId)),
            const SizedBox(height: 8),
            _ActionButton(icon: Icons.videocam_rounded, label: 'Send Video Response',
              onTap: () {
                final name = '$firstName $lastName'.trim();
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CoachVideoResponseScreen(
                    clientId: clientId, clientName: name.isEmpty ? 'Client' : name)));
              }),
          ],
          const SizedBox(height: 8),
          // Internal coach tools — always available.
          _ActionButton(icon: Icons.lock_outline, label: 'Private Notes',
            onTap: () {
              final name = '$firstName $lastName'.trim();
              showCoachNotesSheet(context, ref, clientId, name.isEmpty ? 'Client' : name);
            }),
          const SizedBox(height: 8),
          _ActionButton(icon: Icons.attach_money_rounded, label: 'Set Custom Price',
            onTap: () => _showCustomPriceDialog(context, clientId)),
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
    showModalBottomSheet(
      context: context, backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => sheet);
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
      child: Text(label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)));
  }
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
      events.add({'date': first['logged_at'] as String? ?? '',
        'label': 'First Weight Logged: ${first['weight_kg']}kg',
        'icon': 'weight', 'color': 'tert'});
      if (weights.length > 1) {
        final latest = weights.first;
        events.add({'date': latest['logged_at'] as String? ?? '',
          'label': 'Latest Weight: ${latest['weight_kg']}kg',
          'icon': 'weight', 'color': 'mut'});
      }
    }
    if (photos.isNotEmpty) {
      events.add({'date': photos.last['logged_at'] as String? ?? '',
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
/// Coach sets a custom monthly price for THIS client (overrides their global
/// rate). Leaving it blank and saving clears the override.
void _showCustomPriceDialog(BuildContext context, String clientId) {
  final ctrl = TextEditingController();
  showDialog(
    context: context,
    builder: (dctx) => AlertDialog(
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
          style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700),
            suffixText: '/mo',
            suffixStyle: TextStyle(color: _mut),
            hintText: 'e.g. 150',
            hintStyle: TextStyle(color: _mut),
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: _mut)),
        ),
        TextButton(
          onPressed: () async {
            final raw = ctrl.text.trim();
            final value = raw.isEmpty ? null : double.tryParse(raw);
            await CoachRelationshipService().setClientPrice(clientId, value);
            if (!dctx.mounted) return;
            Navigator.pop(dctx);
            ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(
                content: Text(value == null
                    ? 'Custom price cleared — using your standard rate.'
                    : 'Custom price set to \$${value.toStringAsFixed(0)}/mo.')));
          },
          child: const Text('Save', style: TextStyle(color: _pri, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// Coach insight: the client's chosen training days + time (from onboarding,
/// confirmed when they picked a package).
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
      if (sched == null)
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
  const _ProgressTab({required this.detail});

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
      lastWorkoutStr = (workouts.first['completed_at'] as String? ?? '').split('T')[0];
      // streak: consecutive days with at least one workout (descending)
      final dates = workouts
          .map((w) => (w['completed_at'] as String? ?? '').split('T')[0])
          .toSet().toList()..sort((a, b) => b.compareTo(a));
      if (dates.isNotEmpty) {
        streak = 1;
        for (int i = 1; i < dates.length; i++) {
          final prev = DateTime.parse(dates[i - 1]);
          final curr = DateTime.parse(dates[i]);
          if (prev.difference(curr).inDays == 1) {
            streak++;
          } else break;
        }
      }
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
      avgEnergy = allCheckins.map((c) => (c['energy'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / allCheckins.length;
      avgStress = allCheckins.map((c) => (c['stress_level'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / allCheckins.length;
      avgMood   = allCheckins.map((c) => (c['mood'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / allCheckins.length;
    }
    if (allCheckins.length >= 2) {
      final e1 = (allCheckins.first['energy'] as num?)?.toDouble() ?? 0;
      final e2 = (allCheckins.last['energy'] as num?)?.toDouble() ?? 0;
      energyTrend = e1 > e2 ? '↑ Improving' : e1 < e2 ? '↓ Declining' : '→ Stable';
      final s1 = (allCheckins.first['stress_level'] as num?)?.toDouble() ?? 0;
      final s2 = (allCheckins.last['stress_level'] as num?)?.toDouble() ?? 0;
      stressTrend = s1 < s2 ? '↑ Improving' : s1 > s2 ? '↓ Worsening' : '→ Stable';
    }
    final checkInInsights = <String>[];
    if (avgEnergy < 3) checkInInsights.add('⚠ Consistently low energy — review sleep and recovery');
    if (avgStress > 7) checkInInsights.add('⚠ High chronic stress — consider deload week');
    if (allCheckins.length >= 4 && avgMood < 3) checkInInsights.add('⚠ Low mood pattern — check in via call');
    if (checkInInsights.isEmpty && allCheckins.isNotEmpty) checkInInsights.add('✓ No flags — client trending well');

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
              final dateStr = (w['completed_at'] as String? ?? '').split('T')[0];
              final name = w['workout_name'] as String? ?? w['program_name'] as String? ?? 'Workout';
              final dur  = w['duration_minutes'] as int?;
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
              _IntelStat('Calories', '${nutrition['target_calories'] ?? '—'}', _pri),
              _IntelStat('Protein', '${nutrition['target_protein_g'] ?? '—'}g', _tert),
              _IntelStat('Carbs', '${nutrition['target_carbs_g'] ?? '—'}g', _amber),
            ]),
            const SizedBox(height: 10),
            if (nutrition['target_fat_g'] != null)
              _statRow('Fat Target', '${nutrition['target_fat_g']}g'),
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
                Text((w['logged_at'] as String).split('T')[0],
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
                avgStress >= 7 ? _red : avgStress >= 4 ? _amber : _green),
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
              final energy  = c['energy'] as int?;
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

  void _showPhoto(BuildContext context, String url) => showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (dctx) => GestureDetector(
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
    ),
  );

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
      ])));
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
    final s = ref.watch(clientScoreProvider(clientId)).valueOrNull;
    final cycle = (s?['current_cycle_score'] as num?)?.toInt() ?? 0;
    final lifetime = (s?['lifetime_score'] as num?)?.toInt() ?? 0;
    final level = (s?['level'] as num?)?.toInt() ?? 1;
    final rank = s?['rank'] as String? ?? 'Bronze';
    return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('12 CIRCLE SCORE', style: TextStyle(color: _mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),
      Row(children: [
        _scoreCell('$cycle', 'This month', _tert),
        _scoreCell('$lifetime', 'Lifetime', _pri),
        _scoreCell('Lvl $level', rank, _brand),
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
  final bool paidPlan;
  const _CoachActionCenter({required this.actions, required this.clientId, required this.paidPlan});

  @override
  ConsumerState<_CoachActionCenter> createState() => _CoachActionCenterState();
}

class _CoachActionCenterState extends ConsumerState<_CoachActionCenter> {
  final Set<String> _cleared = {};        // approved or dismissed → hidden
  final Map<String, String> _edited = {}; // text overrides

  String _key(Map<String, String> a) => a['text'] ?? '';
  String _text(Map<String, String> a) => _edited[_key(a)] ?? a['text'] ?? '';

  void _openSheet(Widget sheet) {
    showModalBottomSheet(
      context: context, backgroundColor: _card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => sheet);
  }

  void _approve(Map<String, String> a) {
    final icon = a['icon'] ?? '';
    final opensService = icon == 'fitness' || icon == 'nutrition' || icon == 'habit' || icon == 'checkin';
    // Services stay locked until the client is on a paid plan with this coach.
    if (opensService && !widget.paidPlan) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Locked — the client must subscribe to one of your plans first.'),
        behavior: SnackBarBehavior.floating));
      return;
    }
    // Route to the real action so "Approve" actually does the thing.
    switch (icon) {
      case 'fitness':
        _openSheet(_AssignProgramSheet(clientId: widget.clientId, ref: ref));
        break;
      case 'nutrition':
        _openSheet(_AssignNutritionSheet(clientId: widget.clientId, ref: ref));
        break;
      case 'habit':
        _openSheet(_AssignHabitsSheet(clientId: widget.clientId, ref: ref));
        break;
      case 'checkin':
        showAssignActionItemSheet(context, ref, widget.clientId);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Marked done: ${_text(a)}'),
          behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
    }
    setState(() => _cleared.add(_key(a)));
  }

  void _dismiss(Map<String, String> a) {
    setState(() => _cleared.add(_key(a)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Dismissed: ${_text(a)}'),
      behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1)));
  }

  void _edit(Map<String, String> a) {
    final ctrl = TextEditingController(text: _text(a));
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
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
              if (txt.isNotEmpty) setState(() => _edited[_key(a)] = txt);
            },
            child: const Text('Save', style: TextStyle(color: _brand))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.actions.where((a) => !_cleared.contains(_key(a))).toList();
    return _cardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Coach Action Center',
          style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        // Keep the generated items; let the coach add their own (once paid).
        if (widget.paidPlan)
          TextButton.icon(
            onPressed: () => showAssignActionItemSheet(context, ref, widget.clientId),
            icon: const Icon(Icons.add_rounded, color: _brand, size: 16),
            label: const Text('Add', style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap)),
      ]),
      const SizedBox(height: 10),
      if (visible.isEmpty)
        const Text('All caught up — tap “Add” to assign a custom action item.',
          style: TextStyle(color: _mut, fontSize: 13))
      else ...visible.map((a) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _row(a))),
    ]));
  }

  Widget _row(Map<String, String> a) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _brand.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _brand.withValues(alpha: 0.15))),
    child: Row(children: [
      Icon(_iconFor(a['icon'] ?? ''), color: _brand, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Text(_text(a),
        style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600))),
      _miniBtn('Approve', _tert, () => _approve(a), bold: true),
      _miniBtn('Edit', _pri, () => _edit(a)),
      _miniBtn('Dismiss', _mut, () => _dismiss(a)),
    ]));

  Widget _miniBtn(String label, Color color, VoidCallback onTap, {bool bold = false}) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    child: Text(label, style: TextStyle(fontSize: 11,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)));

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
    return SizedBox(
      width: 72, height: 72,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: pct, strokeWidth: 7,
          backgroundColor: _brd,
          valueColor: AlwaysStoppedAnimation(
            total >= 80 ? _green : total >= 50 ? _pri : _red)),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$total', style: const TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w800)),
          const Text('/100', style: TextStyle(color: _mut, fontSize: 9)),
        ]),
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
      child: Row(children: [
        Icon(icon, color: _brand, size: 18),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        const Icon(Icons.arrow_forward_ios, color: _mut, size: 14),
      ])));
}

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

  @override
  Widget build(BuildContext context) {
    final programsAsync = ref.watch(myProgramsProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Assign Workout Program',
          style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        programsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
          error: (e, _) => const Text('Could not load programs',
              style: TextStyle(color: _mut)),
          data: (programs) => programs.isEmpty
            ? const Text('No programs yet. Create a program first.',
                style: TextStyle(color: _mut))
            : Column(children: programs.map((p) => GestureDetector(
                onTap: () => setState(() => _selectedProgramId = p['id'] as String),
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
                      Text('${p['duration_weeks']} weeks • ${p['goal'] ?? ''}',
                        style: const TextStyle(color: _mut, fontSize: 12)),
                    ])),
                    if (_selectedProgramId == p['id'])
                      const Icon(Icons.check_circle, color: _brand, size: 20),
                  ])))).toList()),
        ),
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
    setState(() => _saving = true);
    await ref.read(coachProgramServiceProvider)
        .assignProgram(_selectedProgramId!, widget.clientId);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Program assigned!'), backgroundColor: _brand));
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

  @override
  void initState() {
    super.initState();
    // Pre-fill with the client's current active plan so the coach can review/edit.
    ref.read(coachProgramServiceProvider).getClientNutritionPlan(widget.clientId).then((p) {
      if (p == null || !mounted) return;
      setState(() {
        _cal.text   = '${p['calories_target'] ?? ''}';
        _pro.text   = '${p['protein_g'] ?? ''}';
        _carb.text  = '${p['carbs_g'] ?? ''}';
        _fat.text   = '${p['fat_g'] ?? ''}';
        _water.text = p['water_target_oz'] == null ? '' : '${p['water_target_oz']}';
        _notes.text = '${p['notes'] ?? ''}';
      });
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
          onPressed: _saving ? null : _save,
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

  Future<void> _save() async {
    final cal  = int.tryParse(_cal.text);
    final pro  = int.tryParse(_pro.text);
    final carb = int.tryParse(_carb.text);
    final fat  = int.tryParse(_fat.text);
    if (cal == null || pro == null || carb == null || fat == null) return;
    setState(() => _saving = true);
    await ref.read(coachProgramServiceProvider).assignNutritionPlan(
      widget.clientId,
      calories: cal, protein: pro, carbs: carb, fat: fat,
      waterOz: int.tryParse(_water.text),
      notes: _notes.text.isEmpty ? null : _notes.text);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nutrition plan saved!'), backgroundColor: _brand));
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

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _presets.length; i++) {
      _vals[i] = TextEditingController(text: '${_presets[i]['default']}');
    }
    // Pre-select habits already assigned + restore their values.
    ref.read(coachProgramServiceProvider).getClientHabits(widget.clientId).then((rows) {
      if (rows.isEmpty || !mounted) return;
      setState(() {
        for (final r in rows) {
          final idx = _presets.indexWhere((p) => p['name'] == r['name']);
          if (idx >= 0) {
            _selected.add(idx);
            if (r['target_value'] != null) _vals[idx]!.text = '${r['target_value']}';
          }
        }
      });
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
      Flexible(child: ListView.separated(
        shrinkWrap: true,
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p   = _presets[i];
          final sel = _selected.contains(i);
          final hasValue = p['value'] == true;
          return GestureDetector(
            onTap: () => setState(() => sel ? _selected.remove(i) : _selected.add(i)),
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
          onPressed: _selected.isEmpty || _saving ? null : _save,
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
    } catch (e, s) {
      reportError('AssignHabitsSheet._save', e, s);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't assign habits — check your connection and try again.")));
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Habits assigned!'), backgroundColor: _brand));
    }
  }
}
