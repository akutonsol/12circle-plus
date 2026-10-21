import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/workout_model.dart';
import '../../domain/week_row.dart';
import '../../domain/workout_provider.dart';
import '../train_palette.dart';

/// FIT-014 · one row of "This week".
///
/// Extracted from `train_hub_screen.dart` for the reason `PillTab` and
/// `NutritionLoadFailed` were: a row that navigates cannot be proven to
/// navigate while it is private to a 1,100-line screen that reads a dozen
/// Supabase-backed providers. The rules it follows are in `domain/week_row.dart`.

class WeekRowTile extends ConsumerWidget {
  final Workout workout;
  const WeekRowTile({super.key, required this.workout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind   = weekRowKind(workout);
    final detail = weekRowDetail(workout);
    final chip   = weekRowChip(workout);
    final done   = kind == WeekRowKind.done;
    final today  = kind == WeekRowKind.today;

    // The board draws every one of these as `<button class="tap row">`. They
    // shipped as `Semantics(button: true)` with no action — a row that
    // announces itself to a screen reader and to the eye and answers neither,
    // which is the same defect FIT-016's session rows carried.
    //
    // The destination is not invented. A week row IS a workout, the package
    // contains exactly one surface for reviewing a workout before committing
    // to it — FIT-016, `/workout-detail`, "review before committing" — and
    // `selectedWorkoutProvider` is the identity mechanism `workout_list_screen`
    // and `active_workout_screen` already use. Committing stays on the hero
    // card's "Begin session"; this is the review path, including for a session
    // already done.
    void open() {
      ref.read(selectedWorkoutProvider.notifier).state = workout;
      context.go('/workout-detail');
    }

    return Semantics(
      button: true,
      label: weekRowLabel(workout),
      excludeSemantics: true,
      // `excludeSemantics` drops the child's ACTIONS with its labels, so the
      // tap is re-declared here (F-20).
      onTap: open,
      child: GestureDetector(
        onTap: open,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: TrainColors.outline.withValues(alpha: 0.4))),
          ),
          child: Row(children: [
            SizedBox(width: 32, child: _marker(kind)),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workout.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            // The board greys a completed title.
                            color: done ? TrainColors.outline : TrainColors.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(detail,
                          style: const TextStyle(
                              color: TrainColors.onSurfaceVar, fontSize: 12.5)),
                    ],
                  ]),
            ),
            if (chip != null)
              today
                  // `.pill` — violet-muted fill, violet text, radius 6, and NO
                  // `text-transform`, so it reads `Now`. The same pill the
                  // hero card above uses.
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: TrainColors.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(chip,
                          style: const TextStyle(
                              color: TrainColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    )
                  // `.mic` — uppercased by the stylesheet.
                  : Text(chip.toUpperCase(), style: trainMicStyle),
          ]),
        ),
      ),
    );
  }

  /// `ph-check` in green, a filled violet dot, or the hollow ring the board
  /// draws on an upcoming session. An undated row has no marker.
  Widget _marker(WeekRowKind kind) => switch (kind) {
        WeekRowKind.done =>
          const Icon(Icons.check, color: TrainColors.tertiary, size: 15),
        WeekRowKind.today => Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(left: 4),
            decoration: const BoxDecoration(
                color: TrainColors.primaryContainer, shape: BoxShape.circle),
          ),
        WeekRowKind.scheduled => Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // `box-shadow: inset 0 0 0 1px var(--dim)` — a ring, not a fill.
              border: Border.all(color: TrainColors.outline, width: 1),
            ),
          ),
        WeekRowKind.undated => const SizedBox.shrink(),
      };
}
