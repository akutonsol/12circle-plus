import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/named_icon_button.dart';
import '../data/models/checkin_model.dart';
import '../domain/checkin_hub.dart';
import '../domain/checkin_provider.dart';

/// FIT-024 · "Check-in detail — `/checkin-detail · with the coach's reply`"
/// and FIT-025 · "Awaiting reply — the empty state with a real answer".
///
/// ── WHAT THIS REPLACED ─────────────────────────────────────────────────────
/// A **23-line stub** reading "Check-in details coming soon" — and FIT-023's
/// history rows, added earlier in this programme, navigated straight into it.
/// The dead end was mine.
///
/// ── WHERE THE WORDS COME FROM ──────────────────────────────────────────────
/// The board, per frame: `Week 13`, `Sent Sunday 31 August`, `What you wrote`,
/// `Replied Monday`, `Reply to Nadia`, `No reply yet`. Its annotation explains
/// the layout: *"The coach's reply is the one card, because it's the reason to
/// come back here. Answers read as label-value rows — quick to scan, and they
/// hold at large Dynamic Type where a table wouldn't."*
///
/// ── TWO PLACES THE BOARD COULD NOT BE FOLLOWED VERBATIM ────────────────────
/// **Pronouns.** The board writes *"She usually replies within a day"* because
/// Nadia is its example. Applying that to a real coach would misgender them, so
/// the sentence is written without a pronoun and says the same thing.
///
/// **A schedule this product does not store.** The board's empty state reads
/// *"Nadia reviews check-ins on Sundays and Mondays."* There is no coach review
/// schedule in the data. Asserting one would be inventing a commitment on a
/// coach's behalf, so it is omitted and recorded as **OD-20**.
class CheckinDetailScreen extends ConsumerWidget {
  const CheckinDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkin = ref.watch(selectedCheckinProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        // FIT-024 declares "Back".
        leading: NamedIconButton(
          label: 'Back',
          onTap: () => context.canPop() ? context.pop() : context.go('/checkins'),
          child: const Icon(Icons.arrow_back, color: _onSurf, size: 20),
        ),
        title: Text(checkin == null ? 'Check-in' : 'Week ${checkin.weekNumber}',
            style: const TextStyle(
                color: _onSurf, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: checkin == null
          // Reached directly, with nothing selected. It states that rather than
          // rendering an empty week as though it were the client's.
          ? const _NothingSelected()
          : _Detail(checkin: checkin),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_note_outlined,
                color: _onSurfV.withValues(alpha: 0.4), size: 40),
            const SizedBox(height: 14),
            const Text('Open a check-in from your history',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _onSurf, fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _Detail extends ConsumerWidget {
  final WeeklyCheckin checkin;
  const _Detail({required this.checkin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = checkinAnswers(checkin);
    final note = checkinNote(checkin);
    final sent = checkinSentLine(checkin);
    final feedback = checkin.feedback;
    final coach = feedback?.coachName.trim();
    final named = coach != null && coach.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (sent != null)
          Text(sent,
              style: TextStyle(
                  color: _onSurfV.withValues(alpha: 0.7), fontSize: 12)),
        const SizedBox(height: 18),

        // ── Answers, as label-value rows ────────────────────────────────────
        if (answers.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(children: [
              for (var i = 0; i < answers.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(children: [
                    Expanded(
                      child: Text(answers[i].label,
                          style: const TextStyle(color: _onSurfV, fontSize: 14)),
                    ),
                    Text(answers[i].value,
                        style: const TextStyle(
                            color: _onSurf,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),

        if (note != null) ...[
          const SizedBox(height: 22),
          Semantics(
            header: true,
            container: true,
            child: const Text('What you wrote',
                style: TextStyle(
                    color: _onSurfV,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4)),
          ),
          const SizedBox(height: 8),
          Text(note,
              style: const TextStyle(color: _onSurf, fontSize: 14, height: 1.5)),
        ],

        const SizedBox(height: 24),

        // ── The coach's reply: "the one card, because it's the reason to come
        //    back here" ──────────────────────────────────────────────────────
        if (feedback != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _brand.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Semantics(
                  header: true,
                  container: true,
                  child: Text(named ? coach : 'Your coach',
                      style: const TextStyle(
                          color: _onSurf,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Text(_repliedLine(feedback.reviewedAt),
                    style: TextStyle(
                        color: _onSurfV.withValues(alpha: 0.7), fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              Text(feedback.message,
                  style:
                      const TextStyle(color: _onSurf, fontSize: 14, height: 1.5)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                container: true,
                // FIT-025's own words.
                child: const Text('No reply yet',
                    style: TextStyle(
                        color: _onSurf,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              // The board continues "<coach> reviews check-ins on Sundays and
              // Mondays." That schedule is not in this product's data, and
              // asserting it would be inventing a commitment on a coach's
              // behalf — OD-20. What is true is said instead.
              Text(
                  checkin.status == CheckinStatus.pending
                      ? 'This check-in has not been sent yet.'
                      : 'Your coach has it. Their reply will appear here.',
                  style: const TextStyle(
                      color: _onSurfV, fontSize: 13, height: 1.5)),
            ]),
          ),

        // ── Reply ───────────────────────────────────────────────────────────
        if (feedback != null) ...[
          const SizedBox(height: 18),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => context.go('/messages'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minHeight: 50),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                // FIT-024 draws "Reply to Nadia" — the coach, by name. The name
                // is real data here (it comes with the reply), so the only
                // fallback needed is for a reply that carries none.
                child: Text(named ? 'Reply to $coach' : 'Reply to your coach',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// `Replied Monday` — the board's phrasing.
  String _repliedLine(DateTime at) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    return 'Replied ${days[at.toLocal().weekday - 1]}';
  }
}

const _bg      = Color(0xFF0B0711);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand   = Color(0xFFA855F7);
const _onSurf  = Color(0xFFDAE2FD);
const _onSurfV = Color(0xFFCFC2D6);
