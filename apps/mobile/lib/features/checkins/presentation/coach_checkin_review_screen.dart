import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../domain/checkin_columns.dart';
import '../domain/checkin_provider.dart';
import '../domain/coach_review_queue.dart' as q;
import '../../auth/domain/auth_provider.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

class CoachCheckinReviewScreen extends ConsumerStatefulWidget {
  const CoachCheckinReviewScreen({super.key});

  @override
  ConsumerState<CoachCheckinReviewScreen> createState() =>
      _CoachCheckinReviewScreenState();
}

class _CoachCheckinReviewScreenState
    extends ConsumerState<CoachCheckinReviewScreen> {
  final _messageCtrl = TextEditingController();
  final _recCtrl = TextEditingController();
  final List<String> _recommendations = [];
  bool _saving = false;

  /// P0-FL-59c · the coach this reply is being written by. The drafts above and
  /// [_open] are theirs; nothing is sent as anyone else.
  String? _owner = checkinUidNow();

  /// Raised when the drafts are dropped, so a send still in flight does not act
  /// on the screen of the account that arrived.
  int _epoch = 0;

  /// The check-in last on screen, kept while the same coach's queue is re-read
  /// and when that fails, so the reply being written does not lose it.
  Map<String, dynamic>? _open;

  bool _holds(int epoch) => epoch == _epoch && checkinUidNow() == _owner;

  /// Drops everything the last coach had on this screen. Says nothing: the one
  /// who arrived is told nothing about it.
  void _drop() {
    _epoch++;
    _owner = checkinUidNow();
    _messageCtrl.clear();
    _recCtrl.clear();
    // What it said to the coach who left is not said to the one who arrived.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..removeCurrentSnackBar();
    setState(() {
      _recommendations.clear();
      _open = null;
      _saving = false;
    });
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _recCtrl.dispose();
    super.dispose();
  }

  void _addRecommendation() {
    final text = _recCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _recommendations.add(text);
      _recCtrl.clear();
    });
  }

  /// Whether an action built at [epoch] may be taken. If not, it belonged to the
  /// coach who left: recorded, and nothing is said.
  bool _mayAct(int epoch, String origin, String what) {
    if (_holds(epoch)) return true;
    reportError(origin, StateError('$what: the signed-in account changed'),
        StackTrace.current);
    if (epoch == _epoch) _drop();
    return false;
  }

  /// [epoch] is the one the button was built at: the coach it is sent as.
  Future<void> _submit(Map<String, dynamic> checkin, int epoch) async {
    if (!_mayAct(epoch, 'CoachCheckinReviewScreen._submit', 'feedback not sent')) {
      return;
    }
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a feedback message.')),
      );
      return;
    }
    setState(() => _saving = true);
    final service = ref.read(weeklyCheckinServiceProvider);
    final coachName = ref.read(currentUserDisplayNameProvider);
    final ok = await service.submitCoachFeedback(
      checkinId: checkin['id'] as String,
      message: _messageCtrl.text.trim(),
      recommendations: _recommendations,
      coachName: coachName,
    );
    if (!mounted) return;
    if (!_holds(epoch)) {
      // Sent by the coach who left: neither its outcome nor the next in their
      // queue belongs to the one who arrived.
      if (epoch == _epoch) _drop();
      return;
    }
    setState(() => _saving = false);

    if (!mounted) return;
    if (ok) {
      // FIT-033's annotation: "Six to review means the flow matters more than
      // the screen ... the primary action is SEND AND OPEN NEXT." Popping back
      // to a list between each of six is the thing the board rejects.
      //
      // The next one is taken from the queue as it was BEFORE the invalidate,
      // because the refreshed queue no longer contains the check-in just
      // reviewed — its status is now `reviewed` — so asking the new queue for
      // "the one after this" has nothing to anchor on.
      final next = q.nextInQueue(_queue(), checkin['id'] as String?);
      ref.invalidate(coachSubmittedCheckinsProvider);
      if (next != null) {
        _messageCtrl.clear();
        _recCtrl.clear();
        setState(_recommendations.clear);
        ref.read(selectedCoachCheckinProvider.notifier).state = next;
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback submitted!')),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit feedback. Try again.')),
      );
    }
  }

  /// The coach's pending queue as currently loaded. Empty while it is in
  /// flight or if the read failed — the header then shows the week alone
  /// rather than a position it cannot know.
  ///
  /// `read`, for CALLBACKS only. The build path must `watch` instead: the
  /// queue is a `FutureProvider`, so on the first frame it is still loading
  /// and its value is absent. Reading it in `build` rendered the header
  /// exactly once, against an empty queue, and never again — `Week 14 · 1 of 6`
  /// would not have appeared in production either. The widget test caught it;
  /// a source assertion that `reviewHeaderLine(` is called would not have.
  ///
  /// Pattern-matched rather than `.valueOrNull`, for the EC-G8 reason: that
  /// getter turns "the queue could not be loaded" into "the queue is empty",
  /// and those are different facts with different consequences — a coach whose
  /// queue failed silently loses `Send and open next` and is never told why.
  List<Map<String, dynamic>> _queue() =>
      _loaded(ref.read(coachSubmittedCheckinsProvider), checkinUidNow);

  /// The queue as [uid]'s coach last read it, kept while it is being re-read —
  /// after a send, or when a `weekly_checkins` notification says one more
  /// arrived (C8) — so the screen does not drop to a spinner under a coach
  /// writing a reply, and kept when that re-read fails, which the screen says. A
  /// queue that was never read is still not a queue: see `_queue()`.
  ///
  /// By the owner the rows carry, NEVER by the kind of state (P0-FL-59c):
  /// Riverpod keeps the last coach's rows in an `AsyncLoading` and an
  /// `AsyncError` too, and those are their clients, with names and notes.
  static List<Map<String, dynamic>> _loaded(
      AsyncValue<List<Map<String, dynamic>>> state, String? Function() uid) {
    final mine = heldFor(state, uid);
    return mine.hasValue ? mine.requireValue : const [];
  }

  /// Advance without sending — FIT-033's declared `Next`.
  void _openNext(Map<String, dynamic> checkin, int epoch) {
    if (!_mayAct(epoch, 'CoachCheckinReviewScreen._openNext', 'next not opened')) {
      return;
    }
    final next = q.nextInQueue(_queue(), checkin['id'] as String?);
    if (next == null) return;
    _messageCtrl.clear();
    _recCtrl.clear();
    setState(_recommendations.clear);
    ref.read(selectedCoachCheckinProvider.notifier).state = next;
  }

  String _clientName(Map<String, dynamic> checkin) =>
      q.clientName(checkin) ?? 'Client';

  @override
  Widget build(BuildContext context) {
    ref.listen(checkinUidProvider, (_, next) {
      if (next != _owner) _drop();
    });
    final epoch = _epoch;
    // Watched, not read — see `_queue()`. The three states are kept apart:
    // a queue that FAILED must not read as a queue that is empty.
    final queueState = ref.watch(coachSubmittedCheckinsProvider);
    final queue = _loaded(queueState, () => ref.watch(checkinUidProvider));
    final queueFailed = queueState is AsyncError;
    final queueFailure = SectionLoadFailure(
      what: 'your review queue',
      error: queueState.error,
      busy: queueState.isLoading,
      onRetry: () => ref.invalidate(coachSubmittedCheckinsProvider),
      accent: AppColors.warning,
    );
    // PD7: every way into this screen (the Check-ins nav item, "Needs you
    // today", the directory tile) arrives with nothing selected, so it said
    // "No check-in selected" and no check-in could ever be opened. With nothing
    // selected, open the oldest submitted one: the queue is read oldest first
    // (`getSubmittedCheckinsForCoach`), and Next / Send and open next page on.
    final checkin = ref.watch(selectedCoachCheckinProvider) ??
        (queue.isNotEmpty ? queue.first : null) ??
        // `_drop` empties `_open`, so it is this coach's.
        (queueFailed || queueState.isLoading ? _open : null);
    _open = checkin;

    if (checkin == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceDark,
          title: const Text("Review Check-In",
              style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.white),
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: switch (queueState) {
            AsyncLoading() => const CircularProgressIndicator(),
            // Not "nothing selected": the coach is about to conclude they have
            // nothing to review, when the truth is that we could not tell.
            AsyncError() =>
              Padding(padding: const EdgeInsets.all(20), child: queueFailure),
            _ => const Text("No check-in selected",
                style: TextStyle(color: AppColors.textSecondary)),
          },
        ),
      );
    }

    final mood = checkin['mood'] as int?;
    // Canonical columns first, legacy as fallback (PD-B02, checkin_columns.dart).
    // These read `energy` / `sleep_hours_avg`, which new rows do not carry.
    final energy = checkinEnergy(checkin)?.toInt();
    final stress = checkin['stress_level'] as int?;
    final sleep = checkinSleepHours(checkin)?.toDouble();
    final notes = checkin['notes'] as String?;
    final score = (checkin['overall_score'] as num?)?.toDouble() ?? 0;
    final weekNumber = checkin['week_number'] as int?;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text("Review Check-In",
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        leading: NamedIconButton(
          label: 'Back',
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back, color: AppColors.white),
        ),
        actions: [
          // FIT-033 declares `Next`: move through the queue WITHOUT sending.
          // Drawn only when there is a next, so it never promises one.
          if (q.nextInQueue(queue, checkin['id'] as String?) != null)
            NamedIconButton(
              label: 'Next',
              onTap: () => _openNext(checkin, epoch),
              child: const Icon(Icons.arrow_forward, color: AppColors.white),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_clientName(checkin),
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    // FIT-033 draws `Week 14 · 1 of 6`. The position is the
                    // feature — see `domain/coach_review_queue.dart`.
                    Builder(builder: (_) {
                      final line = q.reviewHeaderLine(
                        weekNumber: weekNumber,
                        position:
                            q.reviewPosition(queue, checkin['id'] as String?),
                      );
                      if (queueFailed) {
                        // Not "1 of ?" and not silence. The coach is about to
                        // lose `Send and open next` and should know why.
                        return Text(
                            line.isEmpty
                                ? "Couldn't load your review queue"
                                : "$line · couldn't load your review queue",
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 13));
                      }
                      if (line.isEmpty) return const SizedBox.shrink();
                      return Text(line,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13));
                    }),
                  ],
                ),
                if (score > 0)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _scoreColor(score).withValues(alpha: 0.15),
                      border: Border.all(color: _scoreColor(score).withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(score.toStringAsFixed(1),
                        style: TextStyle(
                            color: _scoreColor(score),
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            // The header's few words are not announced and offer no way back.
            if (queueFailed) queueFailure,
            const SizedBox(height: 20),

            // FIT-033's four stats. Only three are produced: `Sessions 4/4` is
            // not recorded anywhere on this row (OD-24), and `Energy` states
            // its value rather than interpreting it (OD-16). The detailed
            // summary below is kept — the board not drawing something is not
            // the same as the design saying to delete it (OD-15's lesson).
            Builder(builder: (_) {
              final stats = q.reviewStats(checkin);
              if (stats.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final st in stats)
                      Expanded(
                        child: Semantics(
                          container: true,
                          label: '${st.label} ${st.value}',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(st.value,
                                  style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(st.label,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),

            const Text("Client Summary",
                style: TextStyle(
                    color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppStyles.premiumCardDecoration,
              child: Column(
                children: [
                  if (mood != null) _SummaryRow("Mood", _moodLabel(mood), Icons.sentiment_satisfied_outlined),
                  if (energy != null) _SummaryRow("Energy", "$energy/5", Icons.bolt),
                  if (stress != null) _SummaryRow("Stress", "$stress/5", Icons.psychology_outlined),
                  if (sleep != null) _SummaryRow("Avg Sleep", "${sleep.toStringAsFixed(1)} hrs", Icons.bedtime_outlined),
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(children: [
                        const Icon(Icons.chat_bubble_outline, color: AppColors.purple, size: 16),
                        const SizedBox(width: 8),
                        // The board writes "She wrote". Amara is its
                        // example; a real client must not be misgendered.
                        Text(q.clientWroteHeading,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(notes,
                        style: const TextStyle(
                            color: AppColors.white, fontSize: 13, height: 1.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(q.coachReplyHeading,
                style: TextStyle(
                    color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              decoration: AppStyles.premiumCardDecoration,
              child: TextField(
                // A new field after a drop: undo in the old one would bring the
                // last coach's words back.
                key: ValueKey('reply-$epoch'),
                controller: _messageCtrl,
                maxLines: 4,
                style: const TextStyle(color: AppColors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Write feedback for this client's week...",
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
              ),
            ),
            const SizedBox(height: 16),

            const Text("Recommendations",
                style: TextStyle(
                    color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: AppStyles.premiumCardDecoration,
                    child: TextField(
                      key: ValueKey('recommendation-$epoch'),
                      controller: _recCtrl,
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "e.g. Add a 4th rest day",
                        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (_) => _addRecommendation(),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _addRecommendation,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
            if (_recommendations.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._recommendations.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.surfaceDarkElevated),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_right, color: AppColors.purple, size: 18),
                          Expanded(
                            child: Text(entry.value,
                                style: const TextStyle(color: AppColors.white, fontSize: 13)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _recommendations.removeAt(entry.key)),
                            child: const Icon(Icons.close, color: AppColors.textTertiary, size: 16),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 32),

            // ── FIT-033's three declared actions ────────────────────────
            Row(children: [
              // `Record`. The board declares it and does not say what it
              // captures. It stays inert — but the reason recorded here was
              // wrong, and is corrected rather than left standing.
              //
              // OD-25 cited QA_EVIDENCE §3ad: "NOTHING in this app sends or
              // renders a video — no capture path, no upload, no player."
              // Two of those three clauses were already false.
              // `coach_video_response_screen.dart` has a capture path
              // (`ImagePicker().pickVideo`) and an upload (`uploadBinary` to
              // `coach-media`), it is reachable from
              // client_detail_screen.dart:359 "Send Video Response", and it
              // even takes the `checkinId` this board would pass.
              //
              // Only the third clause holds, and it is the decisive one:
              // there is NO PLAYER. `coach_video_responses` is written and
              // read nowhere, and the "Tap to watch" notification it sends
              // has no route — notifications_screen.dart:157 marks a tap read
              // and navigates nowhere, for every type. So wiring this button
              // would add a second entrance to a dead end.
              //
              // Inert is still right; "no flow exists" was not why. The
              // missing player is an owner decision, recorded as OD-57, with
              // the public-bucket half as SEC-VIDEO-1.
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Record',
                  enabled: false,
                  excludeSemantics: true,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceDarkElevated),
                    ),
                    child: const Text('Record',
                        style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // `Adjust plan` → `/program-builder`, the route the coach nav
              // itself uses for `Programs` (app_shell.dart:100). Not invented.
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Adjust plan',
                  excludeSemantics: true,
                  onTap: () => context.go('/program-builder'),
                  child: GestureDetector(
                    onTap: () => context.go('/program-builder'),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.surfaceDarkElevated),
                      ),
                      child: const Text('Adjust plan',
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // The primary action. Reads `Send` on the last of the queue,
            // because there is no next to open and a button must not promise
            // one — `Send` is the package's own word (FIT-026's composer).
            Builder(builder: (_) {
              final label = q.primaryActionLabel(
                  q.reviewPosition(queue, checkin['id'] as String?));
              return SizedBox(
                width: double.infinity,
                height: 54,
                child: Semantics(
                  button: true,
                  label: label,
                  enabled: !_saving,
                  excludeSemantics: true,
                  onTap: _saving ? null : () => _submit(checkin, epoch),
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _submit(checkin, epoch),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(label,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 8) return AppColors.success;
    if (score >= 6) return AppColors.warning;
    return AppColors.error;
  }

  String _moodLabel(int mood) {
    const labels = ['', 'Rough', 'Meh', 'Good', 'Great', 'Amazing'];
    if (mood < 1 || mood > 5) return '$mood';
    return labels[mood];
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _SummaryRow(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, color: AppColors.purple, size: 16),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
            Text(value,
                style: const TextStyle(
                    color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
