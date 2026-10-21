import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/animations/app_animations.dart';
import '../domain/habit_provider.dart';
import '../data/models/habit_model.dart';
import '../../../shared/theme/app_background.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../features/coach/data/coach_program_service.dart';
import '../data/habit_reminder_service.dart';
import 'widgets/habit_card.dart';
import '../../../core/widgets/named_icon_button.dart';
import 'package:go_router/go_router.dart';

// ── colour helpers ────────────────────────────────────────────────────────────

Color _catColor(HabitCategory c) {
  switch (c) {
    case HabitCategory.health:       return const Color(0xFF38BDF8);
    case HabitCategory.fitness:      return const Color(0xFF7C3AED);
    case HabitCategory.nutrition:    return const Color(0xFF34D399);
    case HabitCategory.mindfulness:  return const Color(0xFFA78BFA);
    case HabitCategory.sleep:        return const Color(0xFF60A5FA);
  }
}

// ── screen ────────────────────────────────────────────────────────────────────

class HabitScreen extends ConsumerStatefulWidget {
  const HabitScreen({super.key});
  @override
  ConsumerState<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends ConsumerState<HabitScreen> {
  // null = show all ungrouped; set to a category to filter
  HabitCategory? _filterCategory;

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _AddHabitSheet(
        onAdded: () => ref.read(liveHabitNotifierProvider.notifier).reload(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncHabits = ref.watch(liveHabitNotifierProvider);
    final adherence   = ref.watch(adherenceScoreProvider);
    final totalStreak = ref.watch(totalStreakProvider);
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return asyncHabits.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.purple)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          const Text('Failed to load habits',
              style: TextStyle(color: AppColors.white, fontSize: 16)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.read(liveHabitNotifierProvider.notifier).reload(),
            child: const Text('Retry', style: TextStyle(color: AppColors.purple))),
        ])),
      ),
      data: (habits) {
        final completedCount = habits.where((h) => h.isCompletedToday).length;
        final totalCount     = habits.length;
        final completionPct  = totalCount == 0 ? 0.0 : completedCount / totalCount;
        final allDone        = totalCount > 0 && completedCount == totalCount;

        // group by category (sorted)
        final grouped = <HabitCategory, List<Habit>>{};
        for (final cat in HabitCategory.values) {
          final list = habits.where((h) => h.category == cat).toList();
          if (list.isNotEmpty) grouped[cat] = list;
        }

        final visibleCategories = _filterCategory == null
            ? grouped.keys.toList()
            : (grouped.containsKey(_filterCategory!) ? [_filterCategory!] : []);

        return AppGradientBackground(
          child: Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              // ── Hero header ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _HeroHeader(
                  top: top,
                  completedCount: completedCount,
                  totalCount: totalCount,
                  completionPct: completionPct,
                  adherence: adherence,
                  totalStreak: totalStreak,
                  allDone: allDone,
                  onAdd: _showAddSheet,
                  onTestNotif: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await HabitReminderService().sendTestNow();
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(
                      content: Text(kIsWeb
                          ? 'Allow notifications in the browser popup.'
                          : 'Test notification sent.'),
                      duration: const Duration(seconds: 4),
                    ));
                  },
                ),
              ),

              // ── Category filter chips ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: _CategoryChips(
                    grouped: grouped,
                    selected: _filterCategory,
                    onSelect: (cat) => setState(() =>
                        _filterCategory = cat == _filterCategory ? null : cat),
                  ),
                ).fadeSlideIn(delay: 300.ms),
              ),

              // ── Habit groups ───────────────────────────────────────────────
              if (habits.isEmpty)
                SliverToBoxAdapter(child: _EmptyState(onAdd: _showAddSheet))
              else ...[
                for (final cat in visibleCategories) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                      child: _CategoryHeader(
                        category: cat,
                        done: grouped[cat]!.where((h) => h.isCompletedToday).length,
                        total: grouped[cat]!.length,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: HabitCard(habit: grouped[cat]![i])
                              .fadeSlideIn(delay: Duration(milliseconds: 80 * i)),
                        ),
                        childCount: grouped[cat]!.length,
                      ),
                    ),
                  ),
                ],
                if (visibleCategories.isEmpty && _filterCategory != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(child: Text('No ${_filterCategory!.label} habits yet.',
                          style: const TextStyle(color: AppColors.textTertiary))),
                    ),
                  ),
              ],

              SliverToBoxAdapter(child: SizedBox(height: bottom + 120)),
            ],
          ),
        ));
      },
    );
  }
}

// ── Hero header widget ─────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final double top;
  final int completedCount;
  final int totalCount;
  final double completionPct;
  final double adherence;
  final int totalStreak;
  final bool allDone;
  final VoidCallback onAdd;
  final VoidCallback onTestNotif;

  const _HeroHeader({
    required this.top,
    required this.completedCount,
    required this.totalCount,
    required this.completionPct,
    required this.adherence,
    required this.totalStreak,
    required this.allDone,
    required this.onAdd,
    required this.onTestNotif,
  });

  static const _motivations = [
    'Small steps lead to big changes.',
    'Consistency beats perfection.',
    'Every rep counts.',
    'Build the life you want.',
    'Show up. Again.',
  ];

  @override
  Widget build(BuildContext context) {
    final quote = _motivations[DateTime.now().day % _motivations.length];
    final now   = DateTime.now();
    final dayNames = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    final dayStr = '${dayNames[now.weekday - 1]}, ${_monthName(now.month)} ${now.day}';

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // top row
        Row(children: [
          // FIT-058 declares `Back`. The screen had no back control at all —
          // it is reached by a push from the directory, so the only way out
          // was the system gesture.
          NamedIconButton(
            label: 'Back',
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
            child: const Icon(Icons.arrow_back,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('HABITS',
                  style: const TextStyle(color: AppColors.purple, fontSize: 11,
                      fontWeight: FontWeight.w800, letterSpacing: 2.5)),
              const SizedBox(height: 2),
              Text(dayStr,
                  style: const TextStyle(color: AppColors.white, fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          // test notif subtle button
          GestureDetector(
            onTap: onTestNotif,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceDarkElevated)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_outlined, color: AppColors.textTertiary, size: 13),
                SizedBox(width: 4),
                Text('Test', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.purple,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppStyles.purpleGlow,
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: AppColors.white, size: 16),
                SizedBox(width: 4),
                Text('Add', style: TextStyle(color: AppColors.white,
                    fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]).fadeSlideIn(),

        const SizedBox(height: 20),

        // progress + stats row
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // circular dial
          _DialProgress(progress: completionPct, allDone: allDone,
              completed: completedCount, total: totalCount),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // motivational quote
              Text(allDone ? 'All done! Amazing work today 🔥' : quote,
                  style: TextStyle(
                    color: allDone ? AppColors.success : AppColors.textSecondary,
                    fontSize: 13,
                    fontStyle: allDone ? FontStyle.normal : FontStyle.italic,
                  )),
              const SizedBox(height: 14),
              // 3 mini-stats
              Row(children: [
                _MiniStat(label: 'Adherence', value: '${adherence.toInt()}%',
                    color: AppColors.purple),
                const SizedBox(width: 10),
                _MiniStat(label: 'Streak', value: '🔥 $totalStreak',
                    color: const Color(0xFFF97316)),
                const SizedBox(width: 10),
                _MiniStat(label: 'Today', value: '$completedCount/$totalCount',
                    color: AppColors.accentBlue),
              ]),
            ]),
          ),
        ]).fadeSlideIn(delay: 100.ms),
      ]),
    );
  }

  String _monthName(int m) => const [
    '', 'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ][m];
}

class _DialProgress extends StatelessWidget {
  final double progress;
  final bool allDone;
  final int completed;
  final int total;
  const _DialProgress({required this.progress, required this.allDone,
      required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final color = allDone ? AppColors.success : AppColors.purple;
    return SizedBox(
      width: 80, height: 80,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: const Size(80, 80),
            painter: _ArcPainter(progress: progress, color: color)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$completed',
              style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text('of $total',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _ArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const strokeW = 6.0;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: cx - strokeW / 2);

    // track
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false,
        Paint()..color = AppColors.surfaceDarkElevated..style = PaintingStyle.stroke..strokeWidth = strokeW..strokeCap = StrokeCap.round);

    // progress
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false,
          Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = strokeW..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress || old.color != color;
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 9),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── Category chips ────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final Map<HabitCategory, List<Habit>> grouped;
  final HabitCategory? selected;
  final ValueChanged<HabitCategory> onSelect;

  const _CategoryChips({required this.grouped, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: grouped.entries.map((e) {
          final cat     = e.key;
          final done    = e.value.where((h) => h.isCompletedToday).length;
          final total   = e.value.length;
          final isSel   = cat == selected;
          final color   = _catColor(cat);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                AppAnimations.hapticLight();
                onSelect(cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSel ? color.withValues(alpha: 0.18) : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSel ? color : AppColors.surfaceDarkElevated),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${cat.label} $done/$total',
                      style: TextStyle(
                        color: isSel ? color : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.normal,
                      )),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Category section header ───────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  final HabitCategory category;
  final int done;
  final int total;
  const _CategoryHeader({required this.category, required this.done, required this.total});

  static final _icons = {
    HabitCategory.health:       Icons.favorite_outline,
    HabitCategory.fitness:      Icons.fitness_center_outlined,
    HabitCategory.nutrition:    Icons.restaurant_outlined,
    HabitCategory.mindfulness:  Icons.self_improvement_outlined,
    HabitCategory.sleep:        Icons.bedtime_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final color = _catColor(category);
    final allDone = done == total && total > 0;
    return Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(_icons[category] ?? Icons.star_outline, color: color, size: 15),
      ),
      const SizedBox(width: 10),
      Text(category.label.toUpperCase(),
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      const SizedBox(width: 8),
      if (allDone)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success, size: 11),
            const SizedBox(width: 4),
            const Text('All done', style: TextStyle(color: AppColors.success, fontSize: 10,
                fontWeight: FontWeight.w600)),
          ]),
        )
      else
        Text('$done/$total',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      const Spacer(),
      Container(width: 40, height: 1, color: AppColors.surfaceDarkElevated),
    ]);
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.2))),
          child: const Icon(Icons.track_changes_outlined, color: AppColors.purple, size: 32),
        ),
        const SizedBox(height: 16),
        const Text('No habits yet', style: TextStyle(color: AppColors.white, fontSize: 18,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Build winning routines by tracking\ndaily habits that move the needle.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.purple,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppStyles.purpleGlow),
            child: const Text('Add your first habit',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]).fadeSlideIn(delay: 200.ms),
    );
  }
}

// ── Add Habit bottom sheet ─────────────────────────────────────────────────────

class _AddHabitSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddHabitSheet({required this.onAdded});

  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet> {
  final _nameCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'times');
  String _emoji    = '⭐';
  String _category = 'health';
  int    _target   = 1;
  bool   _saving   = false;

  static const _emojis = [
    '⭐','💧','😴','👟','🧘','💊','🏋️','🥗','📵','🥩','🧴','🌿',
    '🏃','🎯','📖','💪','🧠','🫁',
  ];
  static const _categories = [
    ('health', 'Health'),
    ('fitness', 'Fitness'),
    ('nutrition', 'Nutrition'),
    ('mindfulness', 'Mindfulness'),
    ('sleep', 'Sleep'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await CoachProgramService().addCustomHabit(
        name: _nameCtrl.text.trim(),
        emoji: _emoji,
        category: _category,
        targetValue: _target,
        unit: _unitCtrl.text.trim().isEmpty ? 'times' : _unitCtrl.text.trim(),
      );
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to add habit. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.surfaceDarkElevated,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        const Text('New Habit',
            style: TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),

        // emoji row
        const Text('Pick an icon',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _emojis.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final e = _emojis[i];
              final sel = e == _emoji;
              return GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.purple.withValues(alpha: 0.2) : AppColors.bgDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? AppColors.purple : AppColors.surfaceDarkElevated)),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),

        // habit name
        const Text('Habit Name',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Morning Walk',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            prefixText: '$_emoji  ',
            filled: true, fillColor: AppColors.bgDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.surfaceDarkElevated)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.surfaceDarkElevated)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.purple, width: 1.5)),
          ),
        ),
        const SizedBox(height: 18),

        // category
        const Text('Category',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: _categories.map((c) {
            final isSel = c.$1 == _category;
            final cat = HabitCategory.values.firstWhere((hc) => hc.name == c.$1);
            final color = _catColor(cat);
            return GestureDetector(
              onTap: () => setState(() => _category = c.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? color.withValues(alpha: 0.15) : AppColors.bgDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSel ? color : AppColors.surfaceDarkElevated)),
                child: Text(c.$2,
                    style: TextStyle(
                      color: isSel ? color : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.normal,
                    )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),

        // target + unit
        Row(children: [
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Daily Target',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(children: [
              _StepButton(icon: Icons.remove, onTap: () { if (_target > 1) setState(() => _target--); }),
              Expanded(child: Center(
                child: Text('$_target',
                    style: const TextStyle(color: AppColors.white, fontSize: 20,
                        fontWeight: FontWeight.w800)))),
              _StepButton(icon: Icons.add, onTap: () => setState(() => _target++), filled: true),
            ]),
          ])),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Unit',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _unitCtrl,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'times, glasses…',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                filled: true, fillColor: AppColors.bgDark,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.surfaceDarkElevated)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.surfaceDarkElevated)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.purple, width: 1.5)),
              ),
            ),
          ])),
        ]),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.purple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Create Habit',
                    style: TextStyle(color: AppColors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _StepButton({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: filled ? AppColors.purple : AppColors.bgDark,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: AppColors.surfaceDarkElevated),
        ),
        child: Icon(icon, color: AppColors.white, size: 18),
      ),
    );
  }
}
