import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../../core/observability/app_failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/animations/app_animations.dart';
import '../../data/models/habit_model.dart';
import '../../domain/habit_provider.dart';
import 'streak_badge.dart';
import 'habit_progress_ring.dart';
import '../../domain/habit_row.dart';
import '../../../workout/presentation/widgets/section_load_failure.dart'
    show couldntMessage;

class HabitCard extends ConsumerStatefulWidget {
  final Habit habit;

  const HabitCard({super.key, required this.habit});

  @override
  ConsumerState<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends ConsumerState<HabitCard> {
  bool _showCompletion = false;

  /// P0-FL-59e · whose habit this is: the member signed in when it was drawn.
  /// The notifier read at tap time is the one signed in THEN, so it cannot
  /// tell that a card still up is another member's.
  late String? _owner = _signedIn;

  static String? get _signedIn {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } on Error {
      return null; // no client at all: the card alone, in a test
    }
  }

  @override
  void initState() {
    super.initState();
    _owner; // captured now, not at the first tap
  }

  @override
  void didUpdateWidget(HabitCard old) {
    super.didUpdateWidget(old);
    // Another member's list reuses the cards.
    if (old.habit.id != widget.habit.id) _owner = _signedIn;
  }

  /// False (recorded, and silent: it is not their tick) once someone else is
  /// signed in.
  bool _stillOwner() {
    if (_signedIn == _owner) return true;
    reportError('HabitCard.identity',
        StateError('habit log: the signed-in account changed'));
    return false;
  }

  Color get _categoryColor {
    switch (widget.habit.category) {
      case HabitCategory.health:
        return const Color(0xFF38BDF8);
      case HabitCategory.fitness:
        return AppColors.purple;
      case HabitCategory.nutrition:
        return const Color(0xFF34D399);
      case HabitCategory.mindfulness:
        return const Color(0xFFA78BFA);
      case HabitCategory.sleep:
        return const Color(0xFF60A5FA);
    }
  }

  void _onComplete() {
    setState(() => _showCompletion = true);
    AppAnimations.hapticSuccess();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showCompletion = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSimple = widget.habit.targetValue == 1;
    final done = widget.habit.isCompletedToday;

    // A write that did not save is put back by the notifier and said here,
    // never left ticked in silence (EC-12).
    void notSaved(Object? error) {
      if (!mounted || !_stillOwner()) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(couldntMessage('save that', error))));
    }

    Future<void> toggle() async {
      if (!_stillOwner()) return;
      if (!done) _onComplete();
      final id = widget.habit.id;
      final notifier = ref.read(liveHabitNotifierProvider.notifier);
      final ok = await notifier.toggleComplete(id);
      if (!ok) notSaved(notifier.failureOf(id));
    }

    return Stack(
      children: [
        // FIT-058: "Tapping the ROW is the whole interaction — no separate
        // checkbox to hit — with role="checkbox" so the state is announced."
        //
        // What shipped: a 32 x 32 circle as the only tap target (under the
        // 44 dp floor, and FIT-100's annotation measures the same thing —
        // "Toggle is 44px — the source has 32"), NO `Semantics` anywhere, and
        // a completed habit rendered as a plain `Container` so it could not be
        // un-toggled at all.
        //
        // `Semantics(checked:)` is what gives Flutter the checkbox role, so
        // the state is announced in the reader's own language rather than
        // written into the name.
        Semantics(
          checked: done,
          label: habitRowLabel(widget.habit.name, widget.habit.completedDates),
          hint: habitRowHint(completedToday: done),
          excludeSemantics: true,
          onTap: isSimple ? toggle : null,
          child: GestureDetector(
            onTap: isSimple ? toggle : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.habit.isCompletedToday
                    ? _categoryColor.withValues(alpha: 0.1)
                    : AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.habit.isCompletedToday
                      ? _categoryColor.withValues(alpha: 0.3)
                      : AppColors.surfaceDarkElevated,
                ),
                boxShadow: widget.habit.isCompletedToday
                    ? [
                        BoxShadow(
                            color: _categoryColor.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HabitProgressRing(
                        progress: widget.habit.progress,
                        size: 52,
                        color: _categoryColor,
                        child: Text(widget.habit.emoji,
                            style: const TextStyle(fontSize: 20)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.habit.name,
                                style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                '${widget.habit.currentValue} / ${widget.habit.targetValue} ${widget.habit.unit}',
                                key: ValueKey(widget.habit.currentValue),
                                style: TextStyle(
                                    color: _categoryColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            // FIT-058 puts the week on the row — "6 of 7 this
                            // week". It was not shown at all.
                            const SizedBox(height: 2),
                            Text(weekLine(widget.habit.completedDates),
                                style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      // The mark, not the control — the row is the control. It
                      // is excluded from semantics so the row announces once, and
                      // sized to the 44 dp floor because it still reads as the
                      // thing you aim at.
                      if (isSimple)
                        ExcludeSemantics(
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: done ? AppColors.success : null,
                                  shape: BoxShape.circle,
                                  border: done
                                      ? null
                                      : Border.all(
                                          color: AppColors.textTertiary),
                                ),
                                child: Icon(Icons.check,
                                    color: done
                                        ? AppColors.white
                                        : AppColors.textTertiary,
                                    size: 18),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!isSimple) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StreakBadge(streak: widget.habit.currentStreak),
                        Row(
                          children: [
                            const Icon(Icons.swipe_outlined,
                                color: AppColors.textTertiary, size: 14),
                            const SizedBox(width: 4),
                            const Text('Slide to update',
                                style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: _categoryColor,
                        inactiveTrackColor: AppColors.surfaceDarkElevated,
                        thumbColor: _categoryColor,
                        overlayColor: _categoryColor.withValues(alpha: 0.2),
                        thumbShape: _CustomThumbShape(color: _categoryColor),
                        trackHeight: 8,
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 20),
                      ),
                      child: Slider(
                        value: widget.habit.currentValue.toDouble(),
                        min: 0,
                        max: widget.habit.targetValue.toDouble(),
                        divisions: widget.habit.targetValue,
                        onChanged: (value) {
                          if (!_stillOwner()) return;
                          AppAnimations.hapticLight();
                          final id = widget.habit.id;
                          final notifier =
                              ref.read(liveHabitNotifierProvider.notifier);
                          notifier.updateValue(id, value.toInt()).then((ok) {
                            if (!ok) notSaved(notifier.failureOf(id));
                          });
                        },
                        onChangeEnd: (value) {
                          if (_signedIn != _owner) return;
                          if (value >= widget.habit.targetValue) _onComplete();
                        },
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    StreakBadge(streak: widget.habit.currentStreak),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_showCompletion)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CompletionOverlay(onComplete: () {}),
            ),
          ),
      ],
    );
  }
}

class _CustomThumbShape extends SliderComponentShape {
  final Color color;

  const _CustomThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final gripPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 12, fillPaint);
    canvas.drawCircle(center, 12, borderPaint);
    for (int i = -1; i <= 1; i++) {
      canvas.drawCircle(Offset(center.dx + (i * 4), center.dy), 1.5, gripPaint);
    }
  }
}
