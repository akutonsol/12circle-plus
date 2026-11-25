import '../../../core/observability/app_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/theme/app_background.dart';
import '../../auth/domain/auth_provider.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../data/models/goal.dart';
import '../domain/goal_provider.dart';
import '../../../core/widgets/back_leading.dart';

/// Said when a goal action did not persist (QAX-COR-08); [couldntMessage] says
/// the connection instead when the failure IS the connection.
const goalActionFailedMessage =
    "Couldn't update your goal — try again in a moment. If it keeps happening, contact support.";

/// The signed-in account, by id: a token refresh is the same member.
final _goalsUid = currentUserProvider.select((u) => u?.id);

/// Whether [owner] is still signed in, asked after a write came back. False
/// too when the app's providers went with the account in the meantime.
bool _stillFor(ProviderContainer c, String? owner) {
  try {
    return c.read(_goalsUid) == owner;
  } on StateError {
    return false; // the container is disposed
  }
}

/// A failure said where the member is typing; announced when it appears.
Widget _saidHere(String message) => Semantics(
      liveRegion: true,
      container: true,
      child: Text(message,
          style: const TextStyle(color: AppColors.error, fontSize: 13)),
    );

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(myGoalsProvider);
    final uid = ref.watch(_goalsUid);
    // P0-FL-60c · what was read stays on screen while it is read again, and
    // when that fails — but only for the member it was read for.
    final List<Goal>? last =
        goalsAsync.hasValue ? goalsAsync.requireValue : null;
    final kept = last != null &&
        last.isNotEmpty &&
        uid != null &&
        last.every((g) => g.clientId == uid);
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
        onPressed: () => _showAddGoal(context),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Goal', style: TextStyle(color: Colors.white)),
      ),
      body: goalsAsync.when(
        skipLoadingOnReload: kept,
        skipError: kept,
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
                if (goalsAsync.hasError)
                  SectionLoadFailure(
                    what: 'your latest goals',
                    error: goalsAsync.error,
                    busy: goalsAsync.isLoading,
                    onRetry: () => ref.invalidate(myGoalsProvider),
                  ),
                if (active.isNotEmpty) ...[
                  const _Label('Active'),
                  ...active.map((g) => _GoalCard(goal: g, owner: uid)),
                ],
                if (done.isNotEmpty) ...[
                  const _Label('Achieved 🎉'),
                  ...done.map((g) => _GoalCard(goal: g, owner: uid)),
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

  /// Who was signed in when this card was built: the only account its actions
  /// may be sent for.
  final String? owner;
  const _GoalCard({required this.goal, required this.owner});

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
                // The card can go while the write is in flight, its ref with it.
                final c = ProviderScope.containerOf(context, listen: false);
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (c.read(_goalsUid) != owner) {
                  reportError('GoalsScreen.$v',
                      StateError('goal $v: the signed-in account changed'),
                      StackTrace.current);
                  return;
                }
                if (v == 'update') {
                  await _showUpdate(context);
                  return;
                }
                try {
                  if (v == 'complete') {
                    await c.read(goalServiceProvider).complete(goal.id);
                  } else if (v == 'delete') {
                    await c.read(goalServiceProvider).deleteGoal(goal.id);
                  }
                  if (_stillFor(c, owner)) c.invalidate(myGoalsProvider);
                } catch (e, s) {
                  reportError('GoalsScreen.$v', e, s);
                  // Not to whoever signed in meanwhile.
                  if (!_stillFor(c, owner)) return;
                  messenger?.showSnackBar(SnackBar(
                      content: Text(couldntMessage('update your goal', e))));
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

  Future<void> _showUpdate(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => _UpdateProgressDialog(goal: goal, owner: owner),
      );
}

/// P0-FL-60c · the dialog saves, and closes only when the server took it: a
/// failed save (or a number it cannot read) keeps what was typed and says so.
/// It used to close first, losing the value with the failure.
class _UpdateProgressDialog extends ConsumerStatefulWidget {
  final Goal goal;
  final String? owner;
  const _UpdateProgressDialog({required this.goal, required this.owner});
  @override
  ConsumerState<_UpdateProgressDialog> createState() =>
      _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends ConsumerState<_UpdateProgressDialog> {
  late final _ctrl = TextEditingController(
      text: widget.goal.currentValue?.toString() ?? '');
  bool _saving = false;
  String? _failure;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null) {
      setState(() => _failure = 'Enter a number, like 72.5.');
      return;
    }
    final c = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final owner = widget.owner;
    if (c.read(_goalsUid) != owner) {
      reportError(
          'GoalsScreen.update',
          StateError('goal update: the signed-in account changed'),
          StackTrace.current);
      _leave();
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });
    var saved = false;
    Object? error;
    try {
      saved = await c
          .read(goalServiceProvider)
          .updateProgress(widget.goal.id, val);
    } catch (e) {
      error = e; // recorded by the service
    }
    // Not to whoever signed in meanwhile.
    if (!_stillFor(c, owner)) return;
    c.invalidate(myGoalsProvider);
    if (saved) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final said = couldntMessage('update your goal', error);
    if (!mounted) {
      messenger?.showSnackBar(SnackBar(content: Text(said)));
      return;
    }
    setState(() {
      _saving = false;
      _failure = said;
    });
  }

  /// Goes with the member it was opened for, at once and silently.
  void _leave() {
    _ctrl.clear();
    _removeRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_goalsUid, (_, uid) {
      if (uid != widget.owner) _leave();
    });
    final failure = _failure;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: const Text('Update progress',
          style: TextStyle(color: AppColors.white)),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
                suffixText: widget.goal.unit,
                suffixStyle: const TextStyle(color: AppColors.textTertiary),
                hintText: 'Current value',
                hintStyle: const TextStyle(color: AppColors.textTertiary)),
          ),
          if (failure != null) ...[
            const SizedBox(height: 12),
            _saidHere(failure),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textTertiary))),
        TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save',
                style: const TextStyle(color: AppColors.purple))),
      ],
    );
  }
}

/// Removes the route [context] is in (not whatever is on top of it), after
/// this frame: the account can change during a build.
void _removeRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (route.isActive) route.navigator?.removeRoute(route);
  });
  WidgetsBinding.instance.scheduleFrame();
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

void _showAddGoal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddGoalSheet(),
  );
}

class _AddGoalSheet extends ConsumerStatefulWidget {
  const _AddGoalSheet();
  @override
  ConsumerState<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends ConsumerState<_AddGoalSheet> {
  /// Who opened the sheet: what is typed here is theirs alone (P0-FL-60c).
  late final String? _owner;
  String? _failure;
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
  void initState() {
    super.initState();
    _owner = ref.read(_goalsUid);
  }

  /// Nothing of what was typed stays for whoever signed in since.
  void _leave() {
    for (final c in [_title, _start, _target, _unit]) {
      c.clear();
    }
    _removeRoute(context);
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _title.text.trim().isEmpty) return;
    final c = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _saving = true;
      _failure = null;
    });
    var saved = false;
    Object? error;
    try {
      // Refuses, and records, when _owner is no longer signed in.
      saved = await c.read(goalServiceProvider).createGoal(
            owner: _owner,
            title: _title.text.trim(),
            type: _type,
            startValue: double.tryParse(_start.text.trim()),
            targetValue: double.tryParse(_target.text.trim()),
            unit: _unit.text.trim(),
            targetDate: _date,
          );
    } catch (e) {
      error = e; // recorded by the service
    }
    // Not to whoever signed in meanwhile.
    if (!_stillFor(c, _owner)) return;
    if (saved) {
      c.invalidate(myGoalsProvider);
      if (mounted) Navigator.pop(context);
      return;
    }
    final said = couldntMessage('save your goal', error);
    if (!mounted) {
      messenger?.showSnackBar(SnackBar(content: Text(said)));
      return;
    }
    // Said in the sheet, over what they typed: a SnackBar is behind it.
    setState(() {
      _saving = false;
      _failure = said;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_goalsUid, (_, uid) {
      if (uid != _owner) _leave();
    });
    final failure = _failure;
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
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        if (failure != null) ...[
          _saidHere(failure),
          const SizedBox(height: 12),
        ],
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
      ])),
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
