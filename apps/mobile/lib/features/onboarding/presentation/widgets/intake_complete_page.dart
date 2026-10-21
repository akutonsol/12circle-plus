import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../coach/domain/coach_name.dart';
import '../../../coach/domain/coach_provider.dart';

/// FIT-009 · "Intake complete" — `/intake → /home · the success language`.
///
/// ── WHERE THE WORDS COME FROM ──────────────────────────────────────────────
/// All of it is the design package's own, taken from the board:
///
///   "That's everything we needed."
///   "<coach> has your answers and will have your first week ready by
///    tomorrow morning."
///   "While you wait"
///   "Have a look at the exercise library, or log what you ate today."
///   "Go to my home"
///
/// Nothing here is invented. The board carries the **body copy** for every
/// frame, not only the interaction labels the manifest lists — which is worth
/// stating because it had not been used as a copy source before this screen.
///
/// ── AND THE DESIGN NOTE, APPLIED LITERALLY ─────────────────────────────────
/// The board's own annotation: *"Success is quiet: a mark, a sentence, what
/// happens next. No confetti, no celebration animation."* So this is a tick, a
/// sentence and one action. The flow previously had no such state at all — it
/// called `context.go('/home')` the instant the last answer saved, and the
/// client's work ended in a screen transition.
class IntakeCompletePage extends ConsumerWidget {
  final VoidCallback onGoHome;
  const IntakeCompletePage({super.key, required this.onGoHome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The board writes the coach's name into the sentence. It is real data, and
    // `coachAddressed` is the one place that decides whether it is safe to use:
    // a failed read must not name a coach the client may not have. A
    // coach-guided client sees their coach; everyone else gets the same
    // sentence with the subject it is true for.
    final line = coachAddressed(
      ref.watch(assignedCoachProvider),
      withName: (name) =>
          '$name has your answers and will have your first week ready by '
          'tomorrow morning.',
      fallback: 'We have your answers and will have your first week ready by '
          'tomorrow morning.',
    );

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(children: [
            const Spacer(),
            // "a mark" — the board's word, and it is a mark, not a celebration.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: _brand.withValues(alpha: 0.45)),
              ),
              child: const Icon(Icons.check_rounded, color: _brand, size: 28),
            ),
            const SizedBox(height: 22),
            Semantics(
              header: true,
              container: true,
              child: const Text("That's everything we needed.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onSurf, fontSize: 24, fontWeight: FontWeight.w700,
                  height: 1.25)),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              // The board sets this paragraph to a measure, not a width.
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _onSurfV, fontSize: 14, height: 1.5)),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(children: [
                Semantics(
                  header: true,
                  container: true,
                  child: const Text('While you wait',
                    style: TextStyle(
                      color: _onSurfV, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Have a look at the exercise library, or log what you ate today.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurfV, fontSize: 13, height: 1.5)),
              ]),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                child: GestureDetector(
                  onTap: onGoHome,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _btnPurple,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('Go to my home',
                      style: TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

const _bg         = Color(0xFF0B0711);
const _brand      = Color(0xFFA855F7);
const _btnPurple  = Color(0xFF7C3AED);
const _onSurf     = Color(0xFFDAE2FD);
const _onSurfV    = Color(0xFFCFC2D6);
