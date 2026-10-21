import 'package:flutter/material.dart';
import '../domain/coach_surface.dart';
import 'widgets/coach_surface_tabs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_coach_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _pri   = Color(0xFFDDB7FF);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);
const _userBubble = Color(0xFF1A0F2E);

class _Message {
  final String text;
  final bool isUser;
  const _Message(this.text, {required this.isUser});
}

class AICoachScreen extends ConsumerStatefulWidget {
  const AICoachScreen({super.key});
  @override
  ConsumerState<AICoachScreen> createState() => _AICoachScreenState();
}

class _AICoachScreenState extends ConsumerState<AICoachScreen> {
  /// Which of the board's two surfaces is showing. Before this, the screen
  /// chose for the user with `_messages.length <= 1`.
  CoachSurface _surface = CoachSurface.coaching;

  final _svc = AICoachService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  AICoachMode _mode = AICoachMode.general;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await _svc.getConversationHistory(limit: 10);
    if (!mounted) return;
    setState(() {
      for (final h in history) {
        _messages.add(_Message(h['user_message'] as String, isUser: true));
        _messages.add(_Message(h['ai_response'] as String, isUser: false));
      }
    });
    if (_messages.isEmpty) {
      _addWelcome();
    }
    _scrollToBottom();
  }

  void _addWelcome() {
    _messages.add(const _Message(
      'Hey! I\'m your AI Coach. Ask me anything about nutrition, workouts, recovery, or your progress. What\'s on your mind? 💪',
      isUser: false,
    ));
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() {
      _messages.add(_Message(text, isUser: true));
      _loading = true;
      // A suggested prompt is tapped on the coaching surface; the answer
      // arrives on the other one, so the user has to be taken there.
      _surface = surfaceAfterSending(_surface);
    });
    _scrollToBottom();

    try {
      final reply = await _svc.chat(text, _mode);
      if (!mounted) return;
      setState(() => _messages.add(_Message(reply, isUser: false)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Message(
        'Sorry, I\'m having trouble connecting right now. Please try again in a moment.',
        isUser: false,
      )));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _setMode(AICoachMode mode) {
    setState(() {
      _mode = mode;
      _messages.add(_Message(
        'Switched to ${mode.emoji} ${mode.label} mode. Ask me anything!',
        isUser: false,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AI Coach', style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
          Text(_mode.emoji + ' ' + _mode.label,
            style: TextStyle(color: _brand, fontSize: 12)),
        ]),
        actions: [
          PopupMenuButton<AICoachMode>(
            color: _card,
            icon: const Icon(Icons.tune_rounded, color: _mut),
            onSelected: _setMode,
            itemBuilder: (_) => AICoachMode.values.map((m) => PopupMenuItem(
              value: m,
              child: Row(children: [
                Text(m.emoji),
                const SizedBox(width: 10),
                Text(m.label, style: const TextStyle(color: _wht)),
              ]),
            )).toList(),
          ),
        ],
      ),
      body: Column(children: [
        // ── The board's two surfaces ─────────────────────────────────────────
        CoachSurfaceTabs(
          selected: _surface,
          onSelect: (s) => setState(() => _surface = s),
          background: _card,
          accent: _brand,
          border: _brd,
          selectedText: _wht,
          unselectedText: _mut,
        ),
        // ── Mode chips — conversation only (FIT-108/109 declare them there) ──
        if (showsComposer(_surface)) Container(
          color: _card,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [AICoachMode.nutrition, AICoachMode.workout, AICoachMode.general]
                .map((m) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _setMode(m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _mode == m ? _brand : _brd,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _mode == m ? _brand : _brd),
                      ),
                      child: Text('${m.emoji} ${m.label}',
                        style: TextStyle(color: _mode == m ? _wht : _mut, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                )).toList(),
            ),
          ),
        ),
        // ── Coach home (intelligence cards) when chat is empty, else messages ──
        Expanded(
          child: _surface == CoachSurface.coaching
              ? ListView(padding: const EdgeInsets.only(top: 4, bottom: 16), children: [
                  const _DailyInsightCard(),
                  const _MealIdeasCard(),
                  const _ProgressInsightCard(),
                  const _WeeklyReviewCard(),
                  const _GoalPredictionCard(),
                  const _RiskCard(),
                  const _CoachPersonaCard(),
                  const _CoachingMemoryCard(),
                  _SuggestedPrompts(mode: _mode, onTap: (p) { _ctrl.text = p; _send(); }),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) return const _TypingIndicator();
                    return _Bubble(msg: _messages[i]);
                  },
                ),
        ),
        // ── Input — conversation only ────────────────────────────────────────
        if (showsComposer(_surface)) Container(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          decoration: const BoxDecoration(
            color: _card,
            border: Border(top: BorderSide(color: _brd)),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: _wht, fontSize: 14),
                maxLines: 3, minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: askYourCoachHint,
                  hintStyle: const TextStyle(color: _mut),
                  filled: true, fillColor: _bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _brd)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _brd)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _brand)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _brand,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _brand.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 2)],
                ),
                child: const Icon(Icons.send_rounded, color: _wht, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Message msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFA855F7), Color(0xFF6FFBBE)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: _wht, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? _userBubble : _card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: Border.all(color: isUser ? _brand.withValues(alpha: 0.3) : _brd),
              ),
              child: Text(msg.text,
                style: TextStyle(
                  color: isUser ? _pri : _wht,
                  fontSize: 14, height: 1.5)),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFFA855F7), Color(0xFF6FFBBE)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.auto_awesome, color: _wht, size: 16),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _brd)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('AI is thinking', style: TextStyle(color: _mut, fontSize: 13)),
          const SizedBox(width: 8),
          _DotLoader(),
        ]),
      ),
    ]),
  );
}

class _DotLoader extends StatefulWidget {
  @override
  State<_DotLoader> createState() => _DotLoaderState();
}
class _DotLoaderState extends State<_DotLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final delay = i * 0.33;
      final t = (_ctrl.value - delay).clamp(0.0, 1.0);
      final opacity = (t < 0.5 ? t * 2 : (1.0 - t) * 2).clamp(0.3, 1.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Opacity(
          opacity: opacity,
          child: const CircleAvatar(radius: 3, backgroundColor: _brand),
        ),
      );
    })),
  );
}

class _SuggestedPrompts extends StatelessWidget {
  final AICoachMode mode;
  final void Function(String) onTap;
  const _SuggestedPrompts({required this.mode, required this.onTap});

  static const _prompts = {
    AICoachMode.nutrition: [
      'What should I eat after my workout?',
      'I\'m craving something sweet — what fits my macros?',
      'How do I hit my protein goal today?',
    ],
    AICoachMode.workout: [
      'How do I do a Romanian Deadlift correctly?',
      'What can I substitute for pull-ups?',
      'Why are my shoulders not growing?',
    ],
    AICoachMode.general: [
      'How do I break through a plateau?',
      'Should I take rest days?',
      'How do I stay motivated?',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final suggestions = _prompts[mode] ?? _prompts[AICoachMode.general]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        children: suggestions.map((p) => GestureDetector(
          onTap: () => onTap(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _card, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _brd)),
            child: Text(p, style: const TextStyle(color: _pri, fontSize: 12)),
          ),
        )).toList(),
      ),
    );
  }
}

// ── Daily coaching insight card ───────────────────────────────────────────────
class _DailyInsightCard extends StatefulWidget {
  const _DailyInsightCard();
  @override
  State<_DailyInsightCard> createState() => _DailyInsightCardState();
}

class _DailyInsightCardState extends State<_DailyInsightCard> {
  final _svc = AICoachService();
  Map<String, dynamic>? _insight;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = await _svc.getTodayInsight();
    if (!mounted) return;
    // Auto-generate today's brief on open if it doesn't exist yet (bounded to
    // once per day by the per-date dedup), so it's just there each morning.
    if (today == null) { await _generate(); return; }
    if (!mounted) return;
    setState(() { _insight = today; _loading = false; });
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final res = await _svc.generate('daily_insight');
    if (!mounted) return;
    if (res != null) {
      // Shape the engine result like a stored row for display.
      setState(() {
        _insight = {
          'title': res['title'], 'body': res['body'],
          'data': {
            'focus': res['focus'], 'intensity_delta': res['intensity_delta'],
            'nutrition_note': res['nutrition_note'], 'recovery_note': res['recovery_note'],
          },
        };
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate your brief. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = (_insight?['data'] as Map?) ?? const {};
    final delta = (data['intensity_delta'] as num?)?.round() ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0F2E), Color(0xFF0E0B16)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: _pri, size: 18),
          const SizedBox(width: 8),
          const Text("TODAY'S COACHING BRIEF",
            style: TextStyle(color: _pri, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const Spacer(),
          if (_loading)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)),
        ]),
        const SizedBox(height: 12),
        if (_insight == null && !_loading) ...[
          const Text('Get a personalized brief from your data — recovery, adherence, and goals.',
            style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _generate,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
              child: const Text('Generate Today’s Brief',
                style: TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w700))),
          ),
        ] else if (_insight != null) ...[
          Text(_insight!['title']?.toString() ?? 'Today’s Coaching',
            style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_insight!['body']?.toString() ?? '',
            style: const TextStyle(color: _mut, fontSize: 13, height: 1.5)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (data['focus'] != null)
              _chip(Icons.center_focus_strong_rounded, _humanize(data['focus'].toString())),
            if (delta != 0)
              _chip(delta < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                'Intensity ${delta > 0 ? '+' : ''}$delta%',
                color: delta < 0 ? const Color(0xFFF59E0B) : _C2.green),
            if (data['confidence'] != null)
              _chip(Icons.verified_rounded, 'Confidence ${data['confidence']}%',
                color: ((data['confidence'] as num?) ?? 0) < 50 ? const Color(0xFFF59E0B) : _C2.green),
          ]),
          if (data['nutrition_note'] != null) _noteRow(Icons.restaurant_rounded, data['nutrition_note'].toString()),
          if (data['recovery_note'] != null) _noteRow(Icons.self_improvement_rounded, data['recovery_note'].toString()),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _generate,
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('↻ Refresh brief', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600))),
          ),
        ],
      ]),
    );
  }

  Widget _chip(IconData icon, String label, {Color color = _pri}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13), const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]));

  Widget _noteRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: _mut, size: 15), const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: _mut, fontSize: 12, height: 1.4))),
    ]));

  String _humanize(String s) => s.split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _C2 { static const green = Color(0xFF6FFBBE); }

// Shared card shell for the coaching-intelligence cards.
Widget _coachCard({required IconData icon, required String label, Widget? trailing, required Widget child}) =>
  Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A0F2E), Color(0xFF0E0B16)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _brand.withValues(alpha: 0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: _pri, size: 18), const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: _pri, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const Spacer(), if (trailing != null) trailing,
      ]),
      const SizedBox(height: 12),
      child,
    ]),
  );

Widget _genButton(String label, VoidCallback onTap) => GestureDetector(
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w700))));

// ── Weekly review card ────────────────────────────────────────────────────────
class _WeeklyReviewCard extends StatefulWidget {
  const _WeeklyReviewCard();
  @override State<_WeeklyReviewCard> createState() => _WeeklyReviewCardState();
}
class _WeeklyReviewCardState extends State<_WeeklyReviewCard> {
  final _svc = AICoachService();
  Map<String, dynamic>? _review;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final r = await _svc.getLatestReview();
    if (!mounted) return;
    // Auto-generate weekly if there's no review from the last 7 days.
    final stale = r == null || _staleEnd(r['period_end']?.toString());
    if (stale) { await _generate(); return; }
    if (!mounted) return;
    setState(() { _review = r; _loading = false; });
  }
  bool _staleEnd(String? end) {
    final d = end == null ? null : DateTime.tryParse(end);
    return d == null || DateTime.now().difference(d).inDays >= 7;
  }
  Future<void> _generate() async {
    setState(() => _loading = true);
    final res = await _svc.generate('weekly_review');
    if (!mounted) return;
    setState(() {
      if (res != null) _review = {'summary': res['summary'], 'metrics': res['metrics'] ?? {}};
      _loading = false;
    });
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not generate review.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = (_review?['metrics'] as Map?) ?? const {};
    final done = m['workouts_completed'], planned = m['workouts_planned'];
    final wt = (m['weight_change'] as num?);
    return _coachCard(
      icon: Icons.calendar_month_rounded, label: 'WEEKLY REVIEW',
      trailing: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
      child: _review == null && !_loading
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recap your week — workouts, habits, and progress toward your goal.',
                style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              _genButton('Generate Weekly Review', _generate),
            ])
          : _review == null
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_review!['summary']?.toString() ?? '',
                    style: const TextStyle(color: _wht, fontSize: 13, height: 1.5)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (done != null && planned != null) _miniStat('Workouts', '$done/$planned'),
                    if (m['habit_adherence'] != null) _miniStat('Habits', '${m['habit_adherence']}%'),
                    if (wt != null) _miniStat('Weight', '${wt > 0 ? '+' : ''}${wt}'),
                  ]),
                  if (m['next_week_focus'] != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.flag_rounded, color: _pri, size: 15), const SizedBox(width: 8),
                      Expanded(child: Text('Next week: ${m['next_week_focus']}',
                        style: const TextStyle(color: _mut, fontSize: 12, height: 1.4))),
                    ])),
                  GestureDetector(onTap: _generate, child: const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('↻ New review', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)))),
                ]),
    );
  }
  Widget _miniStat(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: _brd, borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(color: _mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: _wht, fontSize: 15, fontWeight: FontWeight.w800)),
    ]));
}

// ── Goal prediction card ──────────────────────────────────────────────────────
class _GoalPredictionCard extends StatefulWidget {
  const _GoalPredictionCard();
  @override State<_GoalPredictionCard> createState() => _GoalPredictionCardState();
}
class _GoalPredictionCardState extends State<_GoalPredictionCard> {
  final _svc = AICoachService();
  Map<String, dynamic>? _pred;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await _svc.getLatestPrediction();
    if (mounted) setState(() { _pred = p; _loading = false; });
  }
  Future<void> _generate() async {
    setState(() => _loading = true);
    final res = await _svc.generate('goal_prediction');
    if (!mounted) return;
    setState(() { if (res != null) _pred = res; _loading = false; });
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not generate prediction.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pace = (_pred?['current_pace'] as num?);
    final date = _pred?['projected_date']?.toString();
    final conf = (_pred?['confidence'] as num?)?.round();
    return _coachCard(
      icon: Icons.insights_rounded, label: 'GOAL PREDICTION',
      trailing: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
      child: _pred == null && !_loading
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Project your goal date from your current pace.',
                style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              _genButton('Predict My Goal Date', _generate),
            ])
          : _pred == null
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('PROJECTED', style: TextStyle(color: _mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Text(date ?? '—', style: const TextStyle(color: _C2_green, fontSize: 18, fontWeight: FontWeight.w800)),
                    ])),
                    if (pace != null) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('PACE', style: TextStyle(color: _mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Text('${pace.abs()}/wk', style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w800)),
                    ]),
                  ]),
                  const SizedBox(height: 10),
                  Text(_pred!['summary']?.toString() ?? '',
                    style: const TextStyle(color: _mut, fontSize: 13, height: 1.5)),
                  if (conf != null) Padding(padding: const EdgeInsets.only(top: 8),
                    child: Text('Confidence: $conf%', style: const TextStyle(color: _pri, fontSize: 11, fontWeight: FontWeight.w600))),
                  GestureDetector(onTap: _generate, child: const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('↻ Re-predict', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)))),
                ]),
    );
  }
}
const _C2_green = Color(0xFF6FFBBE);

// ── Meal ideas card ───────────────────────────────────────────────────────────
class _MealIdeasCard extends StatefulWidget {
  const _MealIdeasCard();
  @override State<_MealIdeasCard> createState() => _MealIdeasCardState();
}
class _MealIdeasCardState extends State<_MealIdeasCard> {
  final _svc = AICoachService();
  List<dynamic> _meals = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final i = await _svc.getLatestInsight('meal_suggestion');
    final m = (i?['data'] as Map?)?['meals'];
    if (mounted) setState(() { _meals = m is List ? m : []; _loading = false; });
  }
  Future<void> _gen() async {
    setState(() => _loading = true);
    final r = await _svc.generate('meal_suggestion');
    if (!mounted) return;
    setState(() { final m = r?['meals']; _meals = m is List ? m : []; _loading = false; });
  }
  @override
  Widget build(BuildContext context) => _coachCard(
    icon: Icons.restaurant_rounded, label: 'MEAL IDEAS',
    trailing: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
    child: _meals.isEmpty && !_loading
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Get meals that fit your remaining macros for today.',
              style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12), _genButton('Suggest Meals', _gen),
          ])
        : _meals.isEmpty ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ..._meals.whereType<Map>().map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(m['name']?.toString() ?? '',
                    style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w700))),
                  Text('${(m['calories'] as num?)?.round() ?? 0} kcal',
                    style: const TextStyle(color: _C2.green, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 2),
                Text('P ${(m['protein_g'] as num?)?.round() ?? 0}g · '
                     'C ${(m['carbs_g'] as num?)?.round() ?? 0}g · '
                     'F ${(m['fat_g'] as num?)?.round() ?? 0}g',
                  style: const TextStyle(color: _mut, fontSize: 11)),
                if (m['note'] != null) Text(m['note'].toString(),
                  style: const TextStyle(color: _mut, fontSize: 11, height: 1.3)),
              ]))),
            GestureDetector(onTap: _gen, child: const Padding(padding: EdgeInsets.only(top: 2),
              child: Text('↻ New ideas', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)))),
          ]),
  );
}

// ── Progress insight card ─────────────────────────────────────────────────────
class _ProgressInsightCard extends StatefulWidget {
  const _ProgressInsightCard();
  @override State<_ProgressInsightCard> createState() => _ProgressInsightCardState();
}
class _ProgressInsightCardState extends State<_ProgressInsightCard> {
  final _svc = AICoachService();
  Map<String, dynamic>? _it;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final i = await _svc.getLatestInsight('progress');
    if (mounted) setState(() { _it = i; _loading = false; });
  }
  Future<void> _gen() async {
    setState(() => _loading = true);
    final r = await _svc.generate('progress_insight');
    if (!mounted) return;
    setState(() { if (r != null) _it = {'title': r['title'], 'body': r['body']}; _loading = false; });
  }
  @override
  Widget build(BuildContext context) => _coachCard(
    icon: Icons.trending_up_rounded, label: 'PROGRESS INSIGHT',
    trailing: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
    child: _it == null && !_loading
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Surface your biggest win from the data — strength, streaks, trends.',
              style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12), _genButton('Find My Win', _gen),
          ])
        : _it == null ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_it!['title']?.toString() ?? '', style: const TextStyle(color: _C2_green, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_it!['body']?.toString() ?? '', style: const TextStyle(color: _mut, fontSize: 13, height: 1.5)),
            GestureDetector(onTap: _gen, child: const Padding(padding: EdgeInsets.only(top: 8),
              child: Text('↻ Refresh', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)))),
          ]),
  );
}

// ── Risk assessment card ──────────────────────────────────────────────────────
class _RiskCard extends StatefulWidget {
  const _RiskCard();
  @override State<_RiskCard> createState() => _RiskCardState();
}
class _RiskCardState extends State<_RiskCard> {
  final _svc = AICoachService();
  Map<String, dynamic>? _it;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final i = await _svc.getLatestInsight('risk');
    if (mounted) setState(() { _it = i; _loading = false; });
  }
  Future<void> _gen() async {
    setState(() => _loading = true);
    final r = await _svc.generate('risk_assessment');
    if (!mounted) return;
    setState(() {
      if (r != null) {
        _it = {'body': r['summary'], 'data': {
          'plateau_risk': r['plateau_risk'], 'churn_risk': r['churn_risk'], 'injury_risk': r['injury_risk']}};
      }
      _loading = false;
    });
  }
  Color _riskColor(num v) => v >= 66 ? const Color(0xFFFFB4AB) : v >= 33 ? const Color(0xFFF59E0B) : _C2_green;
  @override
  Widget build(BuildContext context) {
    final d = (_it?['data'] as Map?) ?? const {};
    return _coachCard(
      icon: Icons.health_and_safety_rounded, label: 'RISK ASSESSMENT',
      trailing: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
      child: _it == null && !_loading
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Spot plateau, drop-off, and injury risk before they happen.',
                style: TextStyle(color: _mut, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12), _genButton('Assess My Risk', _gen),
            ])
          : _it == null ? const SizedBox.shrink()
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _riskStat('Plateau', d['plateau_risk']),
                _riskStat('Drop-off', d['churn_risk']),
                _riskStat('Injury', d['injury_risk']),
              ]),
              const SizedBox(height: 12),
              Text(_it!['body']?.toString() ?? '', style: const TextStyle(color: _mut, fontSize: 13, height: 1.5)),
              GestureDetector(onTap: _gen, child: const Padding(padding: EdgeInsets.only(top: 8),
                child: Text('↻ Re-assess', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)))),
            ]),
    );
  }
  Widget _riskStat(String label, dynamic v) {
    final n = (v as num?)?.round() ?? 0;
    final c = _riskColor(n);
    return Column(children: [
      Text('$n%', style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w800)),
      Text(label.toUpperCase(), style: const TextStyle(color: _mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
    ]);
  }
}

// ── Coach personality card ────────────────────────────────────────────────────
class _CoachPersonaCard extends StatefulWidget {
  const _CoachPersonaCard();
  @override State<_CoachPersonaCard> createState() => _CoachPersonaCardState();
}
class _CoachPersonaCardState extends State<_CoachPersonaCard> {
  final _svc = AICoachService();
  // (style, tone, label)
  static const _styles = [
    ('supportive', 'supportive', 'Supportive'),
    ('motivational', 'energetic', 'Motivational'),
    ('tough_love', 'direct', 'Tough Love'),
    ('educational', 'informative', 'Educational'),
    ('scientific', 'precise', 'Scientific'),
    ('calm', 'calm', 'Calm'),
    ('high_energy', 'high-energy', 'High Energy'),
  ];
  String _style = 'motivational';
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await _svc.getPersona();
    if (mounted) setState(() { _style = (p['style']?.toString() ?? 'motivational'); _loading = false; });
  }
  Future<void> _select(String style, String tone) async {
    setState(() => _style = style);
    await _svc.setPersona(style: style, tone: tone);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coach style updated — your next brief will match.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _coachCard(
      icon: Icons.tune_rounded, label: 'COACH STYLE',
      child: _loading
          ? const SizedBox(height: 20)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Same advice, your preferred delivery.',
                style: TextStyle(color: _mut, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: _styles.map((s) {
                final sel = _style == s.$1;
                return GestureDetector(
                  onTap: () => _select(s.$1, s.$2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? _brand.withValues(alpha: 0.18) : _brd,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? _brand : _brd)),
                    child: Text(s.$3, style: TextStyle(
                      color: sel ? _pri : _mut, fontSize: 12, fontWeight: FontWeight.w600))));
              }).toList()),
            ]),
    );
  }
}

// ── Coaching memory card ──────────────────────────────────────────────────────
class _CoachingMemoryCard extends StatefulWidget {
  const _CoachingMemoryCard();
  @override State<_CoachingMemoryCard> createState() => _CoachingMemoryCardState();
}
class _CoachingMemoryCardState extends State<_CoachingMemoryCard> {
  final _svc = AICoachService();
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;

  static const _kinds = [
    ('like', 'I like', _C2_green),
    ('dislike', 'I dislike', Color(0xFFFFB4AB)),
    ('injury', 'Injury', Color(0xFFF59E0B)),
  ];

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final m = await _svc.getMemories();
    if (mounted) setState(() { _memories = m; _loading = false; });
  }

  Future<void> _add() async {
    final res = await showDialog<(String, String)>(
      context: context, builder: (_) => const _AddMemoryDialog());
    if (res == null) return;
    await _svc.addMemory(res.$1, res.$2);
    await _load();
  }

  Color _kindColor(String kind) {
    for (final k in _kinds) { if (k.$1 == kind) return k.$3; }
    return _pri;
  }

  @override
  Widget build(BuildContext context) {
    return _coachCard(
      icon: Icons.psychology_rounded, label: 'COACHING MEMORY',
      trailing: GestureDetector(
        onTap: _add,
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, color: _pri, size: 16),
          Text('Add', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w700)),
        ])),
      child: _loading
          ? const SizedBox(height: 20)
          : _memories.isEmpty
              ? const Text('Tell your coach what you like, dislike, and any injuries — it remembers and adapts your plan.',
                  style: TextStyle(color: _mut, fontSize: 13, height: 1.4))
              : Wrap(spacing: 8, runSpacing: 8, children: _memories.map((m) {
                  final c = _kindColor(m['kind']?.toString() ?? '');
                  return GestureDetector(
                    // A failed delete used to be silent: the chip simply
                    // reappeared after the refresh, which reads as a glitch
                    // rather than "the fact your coach remembers about you is
                    // still there". These rows include injuries.
                    onLongPress: () async {
                      final ok = await _svc.deleteMemory(m['id'].toString());
                      await _load();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Couldn't remove that. Try again."),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.withValues(alpha: 0.35))),
                      child: Text(m['content']?.toString() ?? '',
                        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600))),
                  );
                }).toList()),
    );
  }
}

class _AddMemoryDialog extends StatefulWidget {
  const _AddMemoryDialog();
  @override State<_AddMemoryDialog> createState() => _AddMemoryDialogState();
}
class _AddMemoryDialogState extends State<_AddMemoryDialog> {
  String _kind = 'like';
  final _ctrl = TextEditingController();
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _card,
    title: const Text('Tell your coach', style: TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: _CoachingMemoryCardState._kinds.map((k) {
        final sel = _kind == k.$1;
        return GestureDetector(
          onTap: () => setState(() => _kind = k.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? k.$3.withValues(alpha: 0.18) : _brd,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? k.$3 : _brd)),
            child: Text(k.$2, style: TextStyle(color: sel ? k.$3 : _mut, fontSize: 12, fontWeight: FontWeight.w600))));
      }).toList()),
      const SizedBox(height: 14),
      TextField(controller: _ctrl, autofocus: true,
        style: const TextStyle(color: _wht),
        decoration: const InputDecoration(
          hintText: 'e.g. hip thrusts / burpees / left knee',
          hintStyle: TextStyle(color: _mut),
          filled: true, fillColor: _brd, border: OutlineInputBorder())),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: _mut))),
      TextButton(
        onPressed: () {
          final t = _ctrl.text.trim();
          if (t.isNotEmpty) Navigator.pop(context, (_kind, t));
        },
        child: const Text('Save', style: TextStyle(color: _pri, fontWeight: FontWeight.w700))),
    ],
  );
}
