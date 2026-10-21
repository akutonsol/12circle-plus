import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/coach_ecosystem_provider.dart';

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _accent = Color(0xFFDDB7FF);

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _difficulties = ['beginner', 'intermediate', 'advanced'];

// ════════════════════════════════════════════════════════════════════════════
// Program Library — coach's reusable programs + create new (Module 31 entry)
// ════════════════════════════════════════════════════════════════════════════
class ProgramLibraryScreen extends ConsumerWidget {
  const ProgramLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(myProgramsProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: const Text('Program Builder',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        icon: const Icon(Icons.add, color: _white),
        label: const Text('New Program', style: TextStyle(color: _white)),
        onPressed: () => _createProgram(context, ref),
      ),
      body: programsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _brand)),
        error: (e, _) => Center(
            child: Text('Could not load programs.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted))),
        data: (programs) {
          if (programs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No programs yet.\nTap “New Program” to build your first training plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: _brand,
            backgroundColor: _card,
            onRefresh: () async => ref.invalidate(myProgramsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: programs.length,
              itemBuilder: (_, i) =>
                  _ProgramCard(program: programs[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createProgram(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ProgramMetaSheet(),
    );
    if (created == null) return;
    final program =
        await ref.read(coachProgramServiceProvider).createProgram(created);
    ref.invalidate(myProgramsProvider);
    if (context.mounted) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProgramBuilderScreen(program: program)));
    }
  }
}

class _ProgramCard extends ConsumerWidget {
  final Map<String, dynamic> program;
  const _ProgramCard({required this.program});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutCount = (program['program_workouts'] is List &&
            (program['program_workouts'] as List).isNotEmpty)
        ? (program['program_workouts'] as List).first['count'] ?? 0
        : 0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProgramBuilderScreen(program: program))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.fitness_center, color: _accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(program['name'] ?? 'Untitled',
                      style: const TextStyle(
                          color: _white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      '${program['duration_weeks'] ?? 12} wks · '
                      '${program['difficulty'] ?? 'intermediate'} · '
                      '$workoutCount workouts',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _muted),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Program Builder — compose workouts (week/day + exercises) for one program
// ════════════════════════════════════════════════════════════════════════════
class ProgramBuilderScreen extends ConsumerWidget {
  final Map<String, dynamic> program;
  const ProgramBuilderScreen({super.key, required this.program});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programId = program['id'] as String;
    final workoutsAsync = ref.watch(programWorkoutsProvider(programId));
    final weeks = (program['duration_weeks'] as int?) ?? 12;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: Text(program['name'] ?? 'Program',
            style: const TextStyle(color: _white, fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            color: _card,
            icon: const Icon(Icons.more_vert, color: _white),
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await _confirmDelete(context);
                if (ok != true) return;
                await ref
                    .read(coachProgramServiceProvider)
                    .deleteProgram(programId);
                ref.invalidate(myProgramsProvider);
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete program',
                      style: TextStyle(color: Color(0xFFFFB4AB)))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        icon: const Icon(Icons.add, color: _white),
        label: const Text('Add Workout', style: TextStyle(color: _white)),
        onPressed: () => _addWorkout(context, ref, programId, weeks),
      ),
      body: workoutsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _brand)),
        error: (e, _) => Center(
            child: Text('Could not load workouts.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted))),
        data: (workouts) {
          if (workouts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No workouts yet.\nTap “Add Workout” to schedule the first session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              ),
            );
          }
          // Group by week.
          final byWeek = <int, List<Map<String, dynamic>>>{};
          for (final w in workouts) {
            final wk = (w['week_number'] as int?) ?? 1;
            byWeek.putIfAbsent(wk, () => []).add(w);
          }
          final weekKeys = byWeek.keys.toList()..sort();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final wk in weekKeys) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
                  child: Text('Week $wk',
                      style: const TextStyle(
                          color: _accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
                ...byWeek[wk]!.map((w) => _WorkoutCard(
                      workout: w,
                      programId: programId,
                      weeks: weeks,
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _addWorkout(BuildContext context, WidgetRef ref,
      String programId, int weeks) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WorkoutEditorSheet(maxWeeks: weeks),
    );
    if (result == null) return;
    await ref
        .read(coachProgramServiceProvider)
        .addWorkoutToProgram(programId, result);
    ref.invalidate(programWorkoutsProvider(programId));
  }

  Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Delete program?',
              style: TextStyle(color: _white)),
          content: const Text(
              'This removes the program and all its workouts. Clients already assigned keep their copy.',
              style: TextStyle(color: _muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: _muted))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(color: Color(0xFFFFB4AB)))),
          ],
        ),
      );
}

class _WorkoutCard extends ConsumerWidget {
  final Map<String, dynamic> workout;
  final String programId;
  final int weeks;
  const _WorkoutCard(
      {required this.workout, required this.programId, required this.weeks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = (workout['exercises'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workout['title'] ?? 'Workout',
                        style: const TextStyle(
                            color: _white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        '${workout['day_of_week'] ?? ''} · '
                        '${workout['estimated_minutes'] ?? 45} min · '
                        '${exercises.length} exercises',
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: _card,
                icon: const Icon(Icons.more_horiz, color: _muted),
                onSelected: (v) async {
                  final svc = ref.read(coachProgramServiceProvider);
                  if (v == 'edit') {
                    final res = await showModalBottomSheet<Map<String, dynamic>>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => _WorkoutEditorSheet(
                          maxWeeks: weeks, existing: workout),
                    );
                    if (res != null) {
                      await svc.updateWorkout(workout['id'] as String, res);
                      ref.invalidate(programWorkoutsProvider(programId));
                    }
                  } else if (v == 'delete') {
                    await svc.deleteWorkout(workout['id'] as String);
                    ref.invalidate(programWorkoutsProvider(programId));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit', style: TextStyle(color: _white))),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Color(0xFFFFB4AB)))),
                ],
              ),
            ],
          ),
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...exercises.map((e) {
              final m = e as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 5, color: _muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${m['name'] ?? ''}  ·  ${m['sets'] ?? '-'}×${m['reps'] ?? '-'}'
                        '${_load(m)}'
                        '${m['rest_seconds'] != null ? '  ·  ${m['rest_seconds']}s rest' : ''}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ── Program metadata sheet (create) ──────────────────────────────────────────
class _ProgramMetaSheet extends StatefulWidget {
  const _ProgramMetaSheet();
  @override
  State<_ProgramMetaSheet> createState() => _ProgramMetaSheetState();
}

class _ProgramMetaSheetState extends State<_ProgramMetaSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _goal = TextEditingController();
  int _weeks = 12;
  String _difficulty = 'intermediate';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'New Program',
      children: [
        _field('Program name', _name, hint: 'e.g. 12-Week Hypertrophy'),
        _field('Goal', _goal, hint: 'e.g. Build muscle'),
        _field('Description', _desc, hint: 'Short summary', maxLines: 2),
        const SizedBox(height: 14),
        const Text('Difficulty',
            style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _difficulties
              .map((d) => ChoiceChip(
                    label: Text(d),
                    selected: _difficulty == d,
                    onSelected: (_) => setState(() => _difficulty = d),
                    backgroundColor: _bg,
                    selectedColor: _brand,
                    labelStyle: TextStyle(
                        color: _difficulty == d ? _white : _muted,
                        fontSize: 12),
                    side: const BorderSide(color: _border),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Duration', style: TextStyle(color: _muted, fontSize: 12)),
            const Spacer(),
            IconButton(
                onPressed: () =>
                    setState(() => _weeks = (_weeks - 1).clamp(1, 52)),
                icon: const Icon(Icons.remove_circle_outline, color: _accent)),
            Text('$_weeks wks',
                style: const TextStyle(
                    color: _white, fontWeight: FontWeight.w700)),
            IconButton(
                onPressed: () =>
                    setState(() => _weeks = (_weeks + 1).clamp(1, 52)),
                icon: const Icon(Icons.add_circle_outline, color: _accent)),
          ],
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: 'Create & build',
          onTap: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'goal': _goal.text.trim(),
              'description': _desc.text.trim(),
              'difficulty': _difficulty,
              'duration_weeks': _weeks,
            });
          },
        ),
      ],
    );
  }
}

// ── Workout editor sheet (add/edit) ──────────────────────────────────────────
class _WorkoutEditorSheet extends StatefulWidget {
  final int maxWeeks;
  final Map<String, dynamic>? existing;
  const _WorkoutEditorSheet({required this.maxWeeks, this.existing});
  @override
  State<_WorkoutEditorSheet> createState() => _WorkoutEditorSheetState();
}

class _WorkoutEditorSheetState extends State<_WorkoutEditorSheet> {
  late TextEditingController _title;
  late TextEditingController _minutes;
  late int _week;
  late String _day;
  late List<Map<String, dynamic>> _exercises;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title'] as String? ?? '');
    _minutes =
        TextEditingController(text: '${e?['estimated_minutes'] ?? 45}');
    _week = (e?['week_number'] as int?) ?? 1;
    _day = (e?['day_of_week'] as String?) ?? 'Monday';
    _exercises = ((e?['exercises'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.existing == null ? 'Add Workout' : 'Edit Workout',
      children: [
        _field('Title', _title, hint: 'e.g. Upper Body Push'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Labeled(
                label: 'Week',
                child: DropdownButton<int>(
                  value: _week,
                  isExpanded: true,
                  dropdownColor: _card,
                  underline: const SizedBox(),
                  style: const TextStyle(color: _white),
                  items: [
                    for (var w = 1; w <= widget.maxWeeks; w++)
                      DropdownMenuItem(value: w, child: Text('Week $w'))
                  ],
                  onChanged: (v) => setState(() => _week = v ?? 1),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Labeled(
                label: 'Day',
                child: DropdownButton<String>(
                  value: _day,
                  isExpanded: true,
                  dropdownColor: _card,
                  underline: const SizedBox(),
                  style: const TextStyle(color: _white),
                  items: _days
                      .map((d) =>
                          DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setState(() => _day = v ?? 'Monday'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field('Estimated minutes', _minutes,
            keyboard: TextInputType.number),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('Exercises',
                style: TextStyle(
                    color: _white, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add, color: _accent, size: 18),
              label: const Text('Add', style: TextStyle(color: _accent)),
            ),
          ],
        ),
        if (_exercises.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No exercises yet.',
                style: TextStyle(color: _muted, fontSize: 12)),
          ),
        ..._exercises.asMap().entries.map((entry) {
          final i = entry.key;
          final ex = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${ex['name']}  ·  ${ex['sets']}×${ex['reps']}'
                    '${_load(ex)}'
                    '${ex['rest_seconds'] != null ? '  ·  ${ex['rest_seconds']}s' : ''}',
                    style: const TextStyle(color: _white, fontSize: 13),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _exercises.removeAt(i)),
                  child: const Icon(Icons.close, color: _muted, size: 18),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: 'Save workout',
          onTap: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'title': _title.text.trim(),
              'week_number': _week,
              'day_of_week': _day,
              'estimated_minutes':
                  int.tryParse(_minutes.text.trim()) ?? 45,
              'exercises': _exercises,
              'sort_order': _days.indexOf(_day),
            });
          },
        ),
      ],
    );
  }

  Future<void> _addExercise() async {
    final ex = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ExerciseDialog(),
    );
    if (ex != null) setState(() => _exercises.add(ex));
  }
}

class _ExerciseDialog extends StatefulWidget {
  const _ExerciseDialog();
  @override
  State<_ExerciseDialog> createState() => _ExerciseDialogState();
}

class _ExerciseDialogState extends State<_ExerciseDialog> {
  final _name = TextEditingController();
  final _sets = TextEditingController(text: '3');
  final _reps = TextEditingController(text: '10');
  final _rest = TextEditingController(text: '60');
  final _weight = TextEditingController();
  String? _error;

  /// A fresh identity for this exercise instance. Random rather than derived
  /// from the name: a coach may legitimately put the same movement in a session
  /// twice, and those are two instances.
  static String _mintInstanceId() =>
      'ex-${DateTime.now().microsecondsSinceEpoch}-'
      '${_seq = (_seq + 1) & 0xffff}';
  static int _seq = 0;

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _reps.dispose();
    _rest.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _card,
      title: const Text('Add exercise', style: TextStyle(color: _white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field('Exercise name', _name, hint: 'e.g. Bench Press'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field('Sets', _sets, keyboard: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field('Reps', _reps, keyboard: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field('Rest s', _rest, keyboard: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 10),
          _field('Load kg (optional)', _weight,
              hint: 'leave blank for no prescribed load',
              keyboard: TextInputType.number),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Color(0xFFE5484D), fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _muted))),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            final sets = int.tryParse(_sets.text.trim());
            final reps = int.tryParse(_reps.text.trim());
            // Nothing leaves this dialog that the contract would reject.
            // `reps` used to be handed on as the raw String, which the client's
            // codec could not read — and the whole program then decoded to
            // nothing at all, so authoring one exercise made the client's
            // program disappear.
            if (name.isEmpty || sets == null || sets < 1 || reps == null || reps < 0) {
              setState(() => _error = 'Name, sets and reps are required, and '
                  'sets and reps must be whole numbers.');
              return;
            }
            Navigator.pop(context, <String, dynamic>{
              // Identity is minted here, once, and travels with the exercise
              // from now on — see docs/WORKOUT_DOMAIN_CONTRACT.md §2.
              'exercise_instance_id': _mintInstanceId(),
              'name': name,
              'sets': sets,
              'reps': reps,
              // A coach who has not prescribed a load prescribes *no* load.
              // Writing 0 would tell the client to lift nothing.
              'weight_kg': double.tryParse(_weight.text.trim()),
              'rest_seconds': int.tryParse(_rest.text.trim()),
            });
          },
          child: const Text('Add', style: TextStyle(color: _accent)),
        ),
      ],
    );
  }
}

// ── Shared sheet widgets ─────────────────────────────────────────────────────
class _SheetScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SheetScaffold({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title,
                  style: const TextStyle(
                      color: _white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _brand,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(
                color: _white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

Widget _field(String label, TextEditingController c,
    {String? hint, int maxLines = 1, TextInputType? keyboard}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: const TextStyle(color: _white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF6B6478)),
            isDense: true,
            filled: true,
            fillColor: _bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _brand),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The prescribed load of a canonical exercise entry, for display.
///
/// Absent load is rendered as nothing at all, never as "0 kg" — a program that
/// prescribes no weight is not a program that prescribes lifting nothing.
String _load(Map<dynamic, dynamic> e) {
  final kg = e['weight_kg'];
  if (kg is! num) return '';
  return '  ·  ${kg % 1 == 0 ? kg.toStringAsFixed(0) : kg}kg';
}
