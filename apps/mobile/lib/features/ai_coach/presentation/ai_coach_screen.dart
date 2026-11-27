import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import '../domain/coach_surface.dart';
import 'widgets/coach_surface_tabs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_coach_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../dashboard/domain/still_reading.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

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

/// The member's AI coach: their conversation, brief, reviews, style and the
/// facts it remembers (P0-FL-62a1).
///
/// Everything on it lives in State, and the State belongs to the member who
/// opened it. So the screen is keyed by the signed-in member's id — by the id
/// only: a token refresh or a profile edit is the same member and keeps the
/// conversation and a half-typed message. Another member signing in, or
/// signing out, replaces the whole screen with a fresh one, read for them.
///
/// Until that rebuild (a frame; a hidden web tab draws none) the old screen is
/// still mounted, so each of its reads, writes and invokes also checks its
/// member against the auth client itself ([AICoachService.owner], and
/// `mounted && !accountLeft(owner)` after every await): nothing of the last
/// member's lands on
/// screen, and nothing is sent as the next one.
class AICoachScreen extends ConsumerWidget {
  const AICoachScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider.select((u) => u?.id));
    return _AICoachBody(key: ValueKey<String?>(uid), owner: boundTo(uid));
  }
}

class _AICoachBody extends ConsumerStatefulWidget {
  const _AICoachBody({super.key, required this.owner});

  /// The member this screen was opened for.
  final String? owner;

  @override
  ConsumerState<_AICoachBody> createState() => _AICoachScreenState();
}

/// P0-FL-62a1 · a card of the member AI coach screen, bound to the member the
/// screen was opened for.
abstract class _OwnedCard extends StatefulWidget {
  const _OwnedCard({required this.owner});
  final String? owner;
}

class _AICoachScreenState extends ConsumerState<_AICoachBody> {
  /// Which of the board's two surfaces is showing. Before this, the screen
  /// chose for the user with `_messages.length <= 1`.
  CoachSurface _surface = CoachSurface.coaching;

  late final _svc = AICoachService(owner: widget.owner);
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  AICoachMode _mode = AICoachMode.general;
  bool _loading = false;

  /// The history read failed: the conversation says so (with a retry) instead
  /// of reopening as a brand-new chat with the welcome message.
  Object? _historyError;
  bool _historyRetrying = false;

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

  /// When this screen's FIRST history request started. Every exchange the
  /// member sends from here is stored server-side (ai_conversations) by the
  /// ai-coach function, so a history retry that succeeds later reads those
  /// back too; rows created at/after this moment belong to this session and
  /// are already on screen.
  DateTime? _historyRequestedAt;

  /// Exchanges stored before this screen opened. A row whose time cannot be
  /// read is kept: dropping it would hide a real earlier exchange.
  bool _isEarlierExchange(Map<String, dynamic> h) {
    final since = _historyRequestedAt;
    if (since == null) return true;
    final at = DateTime.tryParse(h['created_at']?.toString() ?? '');
    return at == null || at.toUtc().isBefore(since);
  }

  Future<void> _loadHistory() async {
    _historyRequestedAt ??= DateTime.now().toUtc();
    final List<Map<String, dynamic>> history;
    try {
      history = await _svc.getConversationHistory(limit: 10);
    } catch (e) {
      // Recorded by the service. No welcome: this is not a new conversation.
      if (!mounted || accountLeft(widget.owner)) return;
      setState(() { _historyError = e; _historyRetrying = false; });
      return;
    }
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() {
      _historyError = null;
      _historyRetrying = false;
      // Earlier exchanges go BEFORE anything said since the screen opened
      // (a retry can succeed after the member has already sent a message),
      // and this session's own exchanges, read back, are not shown twice.
      _messages.insertAll(0, [
        for (final h in history.where(_isEarlierExchange)) ...[
          _Message(h['user_message'] as String, isUser: true),
          _Message(h['ai_response'] as String, isUser: false),
        ],
      ]);
      if (_messages.isEmpty) _addWelcome();
    });
    _scrollToBottom();
  }

  void _retryHistory() {
    if (_historyRetrying) return;
    setState(() => _historyRetrying = true);
    _loadHistory();
  }

  /// One leading row (the failure notice) while the history read has failed.
  int get _historyLead => _historyError != null ? 1 : 0;

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
      if (!mounted || accountLeft(widget.owner)) return;
      setState(() => _messages.add(_Message(reply, isUser: false)));
    } catch (e) {
      if (!mounted || accountLeft(widget.owner)) return;
      setState(() => _messages.add(_Message(
        'Sorry, I\'m having trouble connecting right now. Please try again in a moment.',
        isUser: false,
      )));
    } finally {
      if (mounted && !accountLeft(widget.owner)) setState(() => _loading = false);
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
                  _DailyInsightCard(owner: widget.owner),
                  _MealIdeasCard(owner: widget.owner),
                  _ProgressInsightCard(owner: widget.owner),
                  _WeeklyReviewCard(owner: widget.owner),
                  _GoalPredictionCard(owner: widget.owner),
                  _RiskCard(owner: widget.owner),
                  _CoachPersonaCard(owner: widget.owner),
                  _CoachingMemoryCard(owner: widget.owner),
                  _SuggestedPrompts(mode: _mode, onTap: (p) { _ctrl.text = p; _send(); }),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _historyLead + _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_historyLead == 1 && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionLoadFailure(
                          what: 'your conversation',
                          error: _historyError,
                          busy: _historyRetrying,
                          onRetry: _retryHistory,
                        ),
                      );
                    }
                    final j = i - _historyLead;
                    if (j == _messages.length) return const _TypingIndicator();
                    return _Bubble(msg: _messages[j]);
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
class _DailyInsightCard extends _OwnedCard {
  const _DailyInsightCard({required super.owner});
  @override
  State<_DailyInsightCard> createState() => _DailyInsightCardState();
}

class _DailyInsightCardState extends State<_DailyInsightCard> {
  late final _svc = AICoachService(owner: widget.owner);
  Map<String, dynamic>? _insight;
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }

  Future<void> _load() async {
    final Map<String, dynamic>? today;
    try {
      today = await _svc.getTodayInsight();
    } catch (e) {
      // Not "no brief yet": never generate over a brief that may exist.
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
      return;
    }
    if (!mounted || accountLeft(widget.owner)) return;
    _loadError = null;
    // Auto-generate today's brief on open if it doesn't exist yet (bounded to
    // once per day by the per-date dedup), so it's just there each morning.
    if (today == null) { await _generate(); return; }
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() { _insight = today; _loading = false; });
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final res = await _svc.generate('daily_insight');
    if (!mounted || accountLeft(widget.owner)) return;
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
        SnackBar(content: OwnedText('Could not generate your brief. Try again.', owner: widget.owner)));
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
          // Expanded, not Text + Spacer: at large text on a narrow phone the
          // label wraps instead of overflowing the card (P0-FL-55 round 2).
          const Expanded(child: Text("TODAY'S COACHING BRIEF",
            style: TextStyle(color: _pri, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
          // The failure notice shows its own busy retry; one spinner only.
          if (_loading && _loadError == null)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)),
        ]),
        const SizedBox(height: 12),
        if (_loadError != null)
          SectionLoadFailure(
            what: "today's brief", error: _loadError, busy: _loading, onRetry: _retry)
        else if (_insight == null && !_loading) ...[
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
        // Expanded, not Text + Spacer: at large text sizes on a narrow phone the label wraps
        // instead of pushing the trailing control off the card (P0-FL-55).
        Expanded(child: Text(label, style: const TextStyle(color: _pri, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
        if (trailing != null) trailing,
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
class _WeeklyReviewCard extends _OwnedCard {
  const _WeeklyReviewCard({required super.owner});
  @override State<_WeeklyReviewCard> createState() => _WeeklyReviewCardState();
}
class _WeeklyReviewCardState extends State<_WeeklyReviewCard> {
  late final _svc = AICoachService(owner: widget.owner);
  Map<String, dynamic>? _review;
  bool _loading = true;
  Object? _loadError;

  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    final Map<String, dynamic>? r;
    try {
      r = await _svc.getLatestReview();
    } catch (e) {
      // Not "no recent review": never generate one on a failed read.
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
      return;
    }
    if (!mounted || accountLeft(widget.owner)) return;
    _loadError = null;
    // Auto-generate weekly if there's no review from the last 7 days.
    final stale = r == null || _staleEnd(r['period_end']?.toString());
    if (stale) { await _generate(); return; }
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() { _review = r; _loading = false; });
  }
  bool _staleEnd(String? end) {
    final d = end == null ? null : DateTime.tryParse(end);
    return d == null || DateTime.now().difference(d).inDays >= 7;
  }
  Future<void> _generate() async {
    setState(() => _loading = true);
    final res = await _svc.generate('weekly_review');
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() {
      if (res != null) _review = {'summary': res['summary'], 'metrics': res['metrics'] ?? {}};
      _loading = false;
    });
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: OwnedText('Could not generate review.', owner: widget.owner)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = (_review?['metrics'] as Map?) ?? const {};
    final done = m['workouts_completed'], planned = m['workouts_planned'];
    final wt = (m['weight_change'] as num?);
    return _coachCard(
      icon: Icons.calendar_month_rounded, label: 'WEEKLY REVIEW',
      trailing: _loading && _loadError == null ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
      child: _loadError != null
          ? SectionLoadFailure(
              what: 'your weekly review', error: _loadError, busy: _loading, onRetry: _retry)
          : _review == null && !_loading
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
class _GoalPredictionCard extends _OwnedCard {
  const _GoalPredictionCard({required super.owner});
  @override State<_GoalPredictionCard> createState() => _GoalPredictionCardState();
}
class _GoalPredictionCardState extends State<_GoalPredictionCard> {
  late final _svc = AICoachService(owner: widget.owner);
  Map<String, dynamic>? _pred;
  bool _loading = true;
  Object? _loadError;

  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    try {
      final p = await _svc.getLatestPrediction();
      if (mounted && !accountLeft(widget.owner)) setState(() { _pred = p; _loadError = null; _loading = false; });
    } catch (e) {
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
    }
  }
  Future<void> _generate() async {
    setState(() => _loading = true);
    final res = await _svc.generate('goal_prediction');
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() { if (res != null) _pred = res; _loading = false; });
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: OwnedText('Could not generate prediction.', owner: widget.owner)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pace = (_pred?['current_pace'] as num?);
    final date = _pred?['projected_date']?.toString();
    final conf = (_pred?['confidence'] as num?)?.round();
    return _coachCard(
      icon: Icons.insights_rounded, label: 'GOAL PREDICTION',
      trailing: _loading && _loadError == null ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
      child: _loadError != null
          ? SectionLoadFailure(
              what: 'your goal prediction', error: _loadError, busy: _loading, onRetry: _retry)
          : _pred == null && !_loading
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
class _MealIdeasCard extends _OwnedCard {
  const _MealIdeasCard({required super.owner});
  @override State<_MealIdeasCard> createState() => _MealIdeasCardState();
}
class _MealIdeasCardState extends State<_MealIdeasCard> {
  late final _svc = AICoachService(owner: widget.owner);
  List<dynamic> _meals = [];
  bool _loading = true;
  Object? _loadError;
  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    try {
      final i = await _svc.getLatestInsight('meal_suggestion');
      final m = (i?['data'] as Map?)?['meals'];
      if (mounted && !accountLeft(widget.owner)) setState(() { _meals = m is List ? m : []; _loadError = null; _loading = false; });
    } catch (e) {
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
    }
  }
  Future<void> _gen() async {
    setState(() => _loading = true);
    final r = await _svc.generate('meal_suggestion');
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() { final m = r?['meals']; _meals = m is List ? m : []; _loading = false; });
  }
  @override
  Widget build(BuildContext context) => _coachCard(
    icon: Icons.restaurant_rounded, label: 'MEAL IDEAS',
    trailing: _loading && _loadError == null ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
    child: _loadError != null
        ? SectionLoadFailure(
            what: 'your meal ideas', error: _loadError, busy: _loading, onRetry: _retry)
        : _meals.isEmpty && !_loading
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
class _ProgressInsightCard extends _OwnedCard {
  const _ProgressInsightCard({required super.owner});
  @override State<_ProgressInsightCard> createState() => _ProgressInsightCardState();
}
class _ProgressInsightCardState extends State<_ProgressInsightCard> {
  late final _svc = AICoachService(owner: widget.owner);
  Map<String, dynamic>? _it;
  bool _loading = true;
  Object? _loadError;
  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    try {
      final i = await _svc.getLatestInsight('progress');
      if (mounted && !accountLeft(widget.owner)) setState(() { _it = i; _loadError = null; _loading = false; });
    } catch (e) {
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
    }
  }
  Future<void> _gen() async {
    setState(() => _loading = true);
    final r = await _svc.generate('progress_insight');
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() { if (r != null) _it = {'title': r['title'], 'body': r['body']}; _loading = false; });
  }
  @override
  Widget build(BuildContext context) => _coachCard(
    icon: Icons.trending_up_rounded, label: 'PROGRESS INSIGHT',
    trailing: _loading && _loadError == null ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
    child: _loadError != null
        ? SectionLoadFailure(
            what: 'your progress insight', error: _loadError, busy: _loading, onRetry: _retry)
        : _it == null && !_loading
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
class _RiskCard extends _OwnedCard {
  const _RiskCard({required super.owner});
  @override State<_RiskCard> createState() => _RiskCardState();
}
class _RiskCardState extends State<_RiskCard> {
  late final _svc = AICoachService(owner: widget.owner);
  Map<String, dynamic>? _it;
  bool _loading = true;
  Object? _loadError;
  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    try {
      final i = await _svc.getLatestInsight('risk');
      if (mounted && !accountLeft(widget.owner)) setState(() { _it = i; _loadError = null; _loading = false; });
    } catch (e) {
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
    }
  }
  Future<void> _gen() async {
    setState(() => _loading = true);
    final r = await _svc.generate('risk_assessment');
    if (!mounted || accountLeft(widget.owner)) return;
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
      trailing: _loading && _loadError == null ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _pri)) : null,
      child: _loadError != null
          ? SectionLoadFailure(
              what: 'your risk assessment', error: _loadError, busy: _loading, onRetry: _retry)
          : _it == null && !_loading
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
class _CoachPersonaCard extends _OwnedCard {
  const _CoachPersonaCard({required super.owner});
  @override State<_CoachPersonaCard> createState() => _CoachPersonaCardState();
}
class _CoachPersonaCardState extends State<_CoachPersonaCard> {
  late final _svc = AICoachService(owner: widget.owner);
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

  /// The persona read failed. Until a read is confirmed the member's real
  /// style is unknown, so no style is shown as theirs and no chip is offered:
  /// one tap would otherwise save a default over the persona they chose.
  Object? _loadError;

  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    try {
      final p = await _svc.getPersona();
      if (mounted && !accountLeft(widget.owner)) setState(() { _style = (p['style']?.toString() ?? 'motivational'); _loadError = null; _loading = false; });
    } catch (e) {
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
    }
  }
  /// A style save is in flight.
  bool _saving = false;
  Future<void> _select(String style, String tone) async {
    final previous = _style;
    setState(() { _style = style; _saving = true; });
    final r = await changeCoachStyle(_svc, style: style, tone: tone);
    if (!mounted || accountLeft(widget.owner)) return;
    // A style that was not saved is not shown as chosen.
    setState(() { if (!r.saved) _style = previous; _saving = false; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: OwnedText(r.message, owner: widget.owner)));
  }

  @override
  Widget build(BuildContext context) {
    return _coachCard(
      icon: Icons.tune_rounded, label: 'COACH STYLE',
      child: _loadError != null
          ? SectionLoadFailure(
              what: 'your coach style', error: _loadError, busy: _loading, onRetry: _retry)
          : _loading
          ? const SizedBox(height: 20)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Same advice, your preferred delivery.',
                style: TextStyle(color: _mut, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: _styles.map((s) {
                final sel = _style == s.$1;
                // A 44px target that says what it is and whether it is the
                // member's style; one save at a time (a second tap while one
                // is in flight would race the revert on failure).
                void tap() { if (!_saving) _select(s.$1, s.$2); }
                return Semantics(
                  container: true, button: true, selected: sel, inMutuallyExclusiveGroup: true,
                  enabled: !_saving, label: 'Coach style: ${s.$3}',
                  onTap: _saving ? null : tap, excludeSemantics: true,
                  // Dimmed while a save is in flight so a sighted member sees
                  // the taps are paused, not ignored.
                  child: Opacity(opacity: _saving ? 0.5 : 1, child: GestureDetector(
                    onTap: tap,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: sel ? _brand.withValues(alpha: 0.18) : _brd,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: sel ? _brand : _brd)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(s.$3, style: TextStyle(
                          color: sel ? _pri : _mut, fontSize: 12, fontWeight: FontWeight.w600))),
                      ])))));
              }).toList()),
            ]),
    );
  }
}

// ── Coaching memory card ──────────────────────────────────────────────────────
class _CoachingMemoryCard extends _OwnedCard {
  const _CoachingMemoryCard({required super.owner});
  @override State<_CoachingMemoryCard> createState() => _CoachingMemoryCardState();
}
class _CoachingMemoryCardState extends State<_CoachingMemoryCard> {
  late final _svc = AICoachService(owner: widget.owner);
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;

  static const _kinds = [
    ('like', 'I like', _C2_green),
    ('dislike', 'I dislike', Color(0xFFFFB4AB)),
    ('injury', 'Injury', Color(0xFFF59E0B)),
  ];

  /// The read failed: never "nothing remembered" — that tells the member the
  /// health facts the coach keeps (injuries included) are gone.
  Object? _loadError;

  @override void initState() { super.initState(); _load(); }
  void _retry() {
    if (_loading) return;
    setState(() => _loading = true);
    _load();
  }
  Future<void> _load() async {
    try {
      final m = await _svc.getMemories();
      if (mounted && !accountLeft(widget.owner)) setState(() { _memories = m; _loadError = null; _loading = false; });
    } catch (e) {
      if (mounted && !accountLeft(widget.owner)) setState(() { _loadError = e; _loading = false; });
    }
  }

  Future<void> _add() async {
    // The draft is this member's: it closes, emptied, if another signs in.
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => OpenedByAccount(owner: widget.owner, child: const _AddMemoryDialog()));
    if (res == null) return;
    // Refused (and recorded) by the service if the member has left since.
    final ok = await _svc.addMemory(res.$1, res.$2);
    if (!mounted || accountLeft(widget.owner)) return;
    await _load();
    if (!ok && mounted && !accountLeft(widget.owner)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: OwnedText("Couldn't save that for your coach — try again.", owner: widget.owner)));
    }
  }

  /// Memory ids whose delete is in flight — one delete per memory at a time.
  final _deleting = <String>{};

  // A failed delete used to be silent: the chip simply reappeared after the
  // refresh, which reads as a glitch rather than "the fact your coach
  // remembers about you is still there". These rows include injuries.
  Future<void> _delete(Map<String, dynamic> m) async {
    final id = m['id'].toString();
    if (!_deleting.add(id)) return;
    setState(() {});
    final ok = await _svc.deleteMemory(id);
    if (!mounted || accountLeft(widget.owner)) return;
    await _load();
    if (!mounted || accountLeft(widget.owner)) return;
    setState(() => _deleting.remove(id));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: OwnedText("Couldn't remove that — try again.", owner: widget.owner)),
      );
    }
  }

  Color _kindColor(String kind) {
    for (final k in _kinds) { if (k.$1 == kind) return k.$3; }
    return _pri;
  }

  @override
  Widget build(BuildContext context) {
    return _coachCard(
      icon: Icons.psychology_rounded, label: 'COACHING MEMORY',
      // The only way to add a memory: a named >= 44px button, same look.
      trailing: Semantics(
        container: true, button: true, label: 'Add memory', onTap: _add, excludeSemantics: true,
        child: GestureDetector(
          onTap: _add,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: const Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, color: _pri, size: 16),
              Text('Add', style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w700)),
            ])))),
      child: _loadError != null
          ? SectionLoadFailure(
              what: 'what your coach remembers', error: _loadError, busy: _loading, onRetry: _retry)
          : _loading
          ? const SizedBox(height: 20)
          : _memories.isEmpty
              ? const Text('Tell your coach what you like, dislike, and any injuries — it remembers and adapts your plan.',
                  style: TextStyle(color: _mut, fontSize: 13, height: 1.4))
              : Wrap(spacing: 8, runSpacing: 8, children: _memories.map((m) {
                  final c = _kindColor(m['kind']?.toString() ?? '');
                  final text = m['content']?.toString() ?? '';
                  final busy = _deleting.contains(m['id'].toString());
                  // Long-press was the only way to delete, unlabelled and
                  // invisible to a screen reader: a visible, named 44px
                  // delete plus a semantic action on the chip.
                  return Semantics(
                    container: true,
                    customSemanticsActions: busy ? null : {
                      const CustomSemanticsAction(label: 'Delete memory'): () => _delete(m),
                    },
                    child: GestureDetector(
                      onLongPress: () => _delete(m),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: c.withValues(alpha: 0.35))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text(text,
                            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600))),
                          Semantics(
                            container: true, button: true, enabled: !busy, label: 'Delete memory: $text',
                            onTap: busy ? null : () => _delete(m), excludeSemantics: true,
                            child: IconButton(
                              onPressed: busy ? null : () => _delete(m),
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              padding: EdgeInsets.zero,
                              // A delete in flight shows a 16px spinner in
                              // place of the ✕ (the disabled ✕ never dimmed).
                              icon: busy
                                  ? SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: c))
                                  : Icon(Icons.close_rounded, size: 16, color: c))),
                        ]))),
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

/// Saves the AI coach's style and says what happened.
///
/// `setPersona` answers false when the write fails, and this ignored it: the
/// new style stayed highlighted and the member was told "Coach style updated —
/// your next brief will match" for a style that was never saved.
@visibleForTesting
Future<({bool saved, String message})> changeCoachStyle(AICoachService svc,
    {required String style, required String tone}) async {
  final saved = await svc.setPersona(style: style, tone: tone);
  return (
    saved: saved,
    message: saved
        ? 'Coach style updated — your next brief will match.'
        : "Couldn't change the coach style — try again.",
  );
}
