import '../../../core/observability/app_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/theme/app_background.dart';
import '../data/models/goal.dart';
import '../domain/goal_provider.dart';
import '../../../core/widgets/back_leading.dart';

/// Shown when a goal action did not persist (QAX-COR-08).
void _showGoalFailure(BuildContext context) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(goalActionFailedMessage)));

const goalActionFailedMessage = "Couldn't update your goal — check your connection and try again.";

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(myGoalsProvider);
    return AppGradientBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: backLeading(context),
        title: const Text('My Goals',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _showAddGoal(context, ref),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Goal', style: TextStyle(color: Colors.white)),
      ),
      body: goalsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.purple)),
        error: (_, __) => const Center(
            child: Text('Could not load goals',
                style: TextStyle(color: AppColors.textTertiary))),
        data: (goals) {
          if (goals.isEmpty) return const _Empty();
          final active = goals.where((g) => !g.isCompleted).toList();
          final done = goals.where((g) => g.isCompleted).toList();
          return RefreshIndicator(
            color: AppColors.purple,
            onRefresh: () async => ref.invalidate(myGoalsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              children: [
                if (active.isNotEmpty) ...[
                  const _Label('Active'),
                  ...active.map((g) => _GoalCard(goal: g)),
                ],
                if (done.isNotEmpty) ...[
                  const _Label('Achieved 🎉'),
                  ...done.map((g) => _GoalCard(goal: g)),
                ],
              ],
            ),
          );
        },
      ),
    ));
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.purple,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );
}

class _GoalCard extends ConsumerWidget {
  final Goal goal;
  const _GoalCard({required this.goal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = goal.progress;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceDarkElevated),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(goal.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goal.title,
                  style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Text(goal.label,
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 12)),
            ]),
          ),
          if (!goal.isCompleted)
            PopupMenuButton<String>(
              color: AppColors.surfaceDarkElevated,
              icon: const Icon(Icons.more_horiz, color: AppColors.textTertiary),
              onSelected: (v) async {
                if (v == 'update') {
                  await _showUpdate(context, ref);
                  return;
                }
                try {
                  if (v == 'complete') {
                    await ref.read(goalServiceProvider).complete(goal.id);
                  } else if (v == 'delete') {
                    await ref.read(goalServiceProvider).deleteGoal(goal.id);
                  }
                  ref.invalidate(myGoalsProvider);
                } catch (e, s) {
                  reportError('GoalsScreen.$v', e, s);
                  if (context.mounted) _showGoalFailure(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'update', child: Text('Update progress', style: TextStyle(color: AppColors.white))),
                PopupMenuItem(value: 'complete', child: Text('Mark achieved', style: TextStyle(color: AppColors.white))),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
              ],
            ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: AppColors.surfaceDarkElevated,
            valueColor: AlwaysStoppedAnimation(
                goal.isCompleted ? AppColors.success : AppColors.purple),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
              goal.targetValue != null
                  ? '${goal.currentValue?.toStringAsFixed(goal.currentValue! % 1 == 0 ? 0 : 1) ?? '—'} / ${goal.targetValue!.toStringAsFixed(goal.targetValue! % 1 == 0 ? 0 : 1)} ${goal.unit}'
                  : '${(pct * 100).round()}% complete',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text('${(pct * 100).round()}%',
              style: TextStyle(
                  color: goal.isCompleted ? AppColors.success : AppColors.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
        if (goal.targetDate != null && !goal.isCompleted) ...[
          const SizedBox(height: 6),
          Text('Target: ${goal.targetDate!.month}/${goal.targetDate!.day}/${goal.targetDate!.year}',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        ],
      ]),
    );
  }

  Future<void> _showUpdate(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
        text: goal.currentValue?.toString() ?? '');
    final val = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Update progress',
            style: TextStyle(color: AppColors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
              suffixText: goal.unit,
              suffixStyle: const TextStyle(color: AppColors.textTertiary),
              hintText: 'Current value',
              hintStyle: const TextStyle(color: AppColors.textTertiary)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textTertiary))),
          TextButton(
              onPressed: () =>
                  Navigator.pop(dctx, double.tryParse(ctrl.text.trim())),
              child: const Text('Save',
                  style: TextStyle(color: AppColors.purple))),
        ],
      ),
    );
    if (val != null) {
      final ok = await ref.read(goalServiceProvider).updateProgress(goal.id, val);
      ref.invalidate(myGoalsProvider);
      if (!ok && context.mounted) _showGoalFailure(context);
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.flag_rounded,
              color: AppColors.purple.withValues(alpha: 0.4), size: 56),
          const SizedBox(height: 16),
          const Text('No goals yet',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Tap "New Goal" to set your first target.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        ]),
      );
}

void _showAddGoal(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddGoalSheet(ref: ref),
  );
}

class _AddGoalSheet extends StatefulWidget {
  final WidgetRef ref;
  const _AddGoalSheet({required this.ref});
  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  final _title = TextEditingController();
  final _start = TextEditingController();
  final _target = TextEditingController();
  final _unit = TextEditingController();
  String _type = 'weight_loss';
  DateTime? _date;
  bool _saving = false;

  static const _types = [
    ('weight_loss', '⚖️ Weight Loss'),
    ('muscle_gain', '💪 Muscle Gain'),
    ('body_fat', '🔥 Body Fat'),
    ('event_prep', '🎯 Event Prep'),
    ('wellness', '🌿 Wellness'),
    ('performance', '🏃 Performance'),
  ];

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final ok = await widget.ref.read(goalServiceProvider).createGoal(
          title: _title.text.trim(),
          type: _type,
          startValue: double.tryParse(_start.text.trim()),
          targetValue: double.tryParse(_target.text.trim()),
          unit: _unit.text.trim(),
          targetDate: _date,
        );
    if (!mounted) return;
    if (ok) {
      widget.ref.invalidate(myGoalsProvider);
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save goal.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color: AppColors.bgDarkSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppColors.surfaceDarkElevated,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 18),
        const Text('New Goal',
            style: TextStyle(
                color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _field(_title, 'Goal title (e.g. Lose 5kg by summer)', autofocus: true),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _types.map((tp) {
            final sel = _type == tp.$1;
            return GestureDetector(
              onTap: () => setState(() => _type = tp.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.purple : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? AppColors.purple : AppColors.surfaceDarkElevated),
                ),
                child: Text(tp.$2,
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field(_start, 'Start', keyboard: true)),
          const SizedBox(width: 10),
          Expanded(child: _field(_target, 'Target', keyboard: true)),
          const SizedBox(width: 10),
          SizedBox(width: 70, child: _field(_unit, 'kg')),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 30)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            if (picked != null && mounted) setState(() => _date = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceDarkElevated)),
            child: Row(children: [
              const Icon(Icons.event, color: AppColors.purple, size: 18),
              const SizedBox(width: 10),
              Text(
                  _date == null
                      ? 'Target date (optional)'
                      : '${_date!.month}/${_date!.day}/${_date!.year}',
                  style: TextStyle(
                      color: _date == null
                          ? AppColors.textTertiary
                          : AppColors.white,
                      fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Goal'),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String hint,
          {bool keyboard = false, bool autofocus = false}) =>
      TextField(
        controller: c,
        autofocus: autofocus,
        keyboardType: keyboard
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(color: AppColors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          filled: true,
          fillColor: AppColors.surfaceDark,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
