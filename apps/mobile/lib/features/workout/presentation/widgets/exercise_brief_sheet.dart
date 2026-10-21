import 'package:flutter/material.dart';

import '../../domain/exercise_brief.dart';

/// FIT-016 · the surface the session row's info control opens.
///
/// `exercise_brief.dart` records why this exists and what constrains it. In
/// short: the board's annotation decides the behaviour ("The info icon opens
/// form and instructions"), the package contains no drawn frame for it, and so
/// every visual choice below comes from something the package *does* specify —
///
///   * `surface` `#121215` — the design system's own "Cards, sheets, rows";
///   * `border-radius: 24px 24px 0 0` — the sheet-top shape the board uses in
///     seven places, rather than a number chosen here;
///   * 240 ms present/dismiss — the system's stated sheet duration;
///   * `Done` — the package's own dismissal word, used in five other frames;
///   * the 44 dp `tap` floor.
///
/// There are **no section headings**. `Form` and `Instructions` appear nowhere
/// in the package; prose reads as prose and ordered steps read as ordered
/// steps, which is what they are.
Future<void> showExerciseBrief(BuildContext context, ExerciseBrief brief) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // The system states 240 ms for sheet present/dismiss. Flutter's defaults
    // are 250/200, so both are set rather than left to the framework.
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 240),
      reverseDuration: Duration(milliseconds: 240),
    ),
    builder: (_) => _ExerciseBriefSheet(brief: brief),
  );
}

class _ExerciseBriefSheet extends StatelessWidget {
  final ExerciseBrief brief;
  const _ExerciseBriefSheet({required this.brief});

  @override
  Widget build(BuildContext context) {
    final meta = [brief.muscleGroup, brief.equipment]
        .whereType<String>()
        .toList(growable: false);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          // A grabber. Decorative, and excluded so it is not announced.
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _dim.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              shrinkWrap: true,
              children: [
                Semantics(
                  header: true,
                  container: true,
                  child: Text(brief.name,
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.4)),
                ),
                const SizedBox(height: 6),
                Text(brief.prescription,
                    style: const TextStyle(color: _grey, fontSize: 13)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta.join(' · '),
                      style: const TextStyle(color: _dim, fontSize: 12)),
                ],

                // The coach's note on this slot leads, because it is the most
                // specific guidance that exists for this movement today.
                if (brief.coachNote != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(brief.coachNote!,
                        style: const TextStyle(
                            color: _ink, fontSize: 14, height: 1.55)),
                  ),
                ],

                if (brief.form != null) ...[
                  const SizedBox(height: 18),
                  Text(brief.form!,
                      style: const TextStyle(
                          color: _grey, fontSize: 14, height: 1.6)),
                ],

                if (brief.steps.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  for (var i = 0; i < brief.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: _dim,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 1.54)),
                          ),
                          Expanded(
                            child: Text(brief.steps[i],
                                style: const TextStyle(
                                    color: _ink, fontSize: 14, height: 1.55)),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: 'Done',
                excludeSemantics: true,
                // `excludeSemantics` drops the child's ACTIONS along with its
                // labels, so the tap is re-declared here. Shipping a control
                // that reads `tap=false` is how F-20 happened.
                onTap: () => Navigator.of(context).maybePop(),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _surfaceHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('Done',
                        style: TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

const _surface     = Color(0xFF121215); // design system `surface`
const _surfaceHigh = Color(0xFF1B1B20); // design system `surfaceHigh`
const _ink         = Color(0xFFF4F3F6); // `textPrimary`
const _grey        = Color(0xFF9B96A3); // `textSecondary`
const _dim         = Color(0xFF8B8595); // `textTertiary`
