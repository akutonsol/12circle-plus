import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../auth/domain/auth_provider.dart';
import '../domain/exercise_database_provider.dart';
import '../domain/custom_exercise_provider.dart';
import '../data/exercise_database_service.dart';
import '../data/custom_exercise_service.dart';
import '../data/models/exercise_detail_model.dart';

class _C {
  static const bg                   = Color(0xFF0E0E0F);
  static const surfaceContainerHigh = Color(0xFF2A2A2B);
  static const surfaceContainerMax  = Color(0xFF353436);
  static const glassCard            = Color(0x99201F20);
  static const primary              = Color(0xFFDDB7FF);
  static const primaryContainer     = Color(0xFFB76DFF);
  static const onSurface            = Color(0xFFE5E2E3);
  static const onSurfaceVar         = Color(0xFFCDC3D0);
  static const outline              = Color(0xFF968E99);
  static const outlineVar           = Color(0xFF4B444F);
  static const tertiary             = Color(0xFF6FFBBE);
  static const secondary            = Color(0xFFADC6FF);
  static const amber                = Color(0xFFFFD580);
}

class ExerciseDatabaseScreen extends ConsumerStatefulWidget {
  const ExerciseDatabaseScreen({super.key});
  @override
  ConsumerState<ExerciseDatabaseScreen> createState() => _ExerciseDatabaseScreenState();
}

class _ExerciseDatabaseScreenState extends ConsumerState<ExerciseDatabaseScreen> {
  final _searchCtrl = TextEditingController();
  String _search           = '';
  String _selectedCategory = 'All';
  String _selectedMuscle   = 'All';
  String _selectedEquipment= 'All';
  String _selectedDifficulty = 'All';
  final _service = ExerciseDatabaseService();
  bool _enriching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Coach/admin bulk video enrichment — resolves real embeddable YouTube ids for
  /// every exercise name (built-in library + custom) via the edge function, in
  /// batches, and caches them so they play in-app.
  Future<void> _runVideoEnrichment() async {
    if (_enriching) return;
    final names = <String>{
      for (final e in _service.getAllExercises()) e.name,
    }.where((n) => n.trim().isNotEmpty).toList();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _enriching = true);
    var total = 0;
    var failedBatch = false;
    try {
      const batch = 40;
      for (var i = 0; i < names.length; i += batch) {
        final slice = names.sublist(i, (i + batch).clamp(0, names.length));
        final updated = await CustomExerciseService().enrichExerciseVideos(slice);
        if (updated == null) { failedBatch = true; break; }
        total += updated;
      }
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(failedBatch
          ? 'Video enrichment failed — check YOUTUBE_API_KEY / deploy.'
          : 'Video enrichment done — $total exercises now have an in-app video.'),
      backgroundColor: failedBatch ? const Color(0xFFFFB4AB) : _C.primaryContainer));
  }

  @override
  Widget build(BuildContext context) {
    // ── Hardcoded library ──────────────────────────────────────────────────────
    final builtIn = _service.getAllExercises();

    // ── Supabase custom exercises (coach's + global approved) ─────────────────
    final myAsync     = ref.watch(myExercisesProvider);
    final globalAsync = ref.watch(globalApprovedExercisesProvider);

    final custom = [
      ...myAsync.whenOrNull(data: (d) => d) ?? [],
      ...globalAsync.whenOrNull(data: (d) => d) ?? [],
    ];

    // Deduplicate by id (custom may overlap global approved)
    final seenIds = <String>{};
    final allExercises = <ExerciseDetail>[];
    for (final ex in [...builtIn, ...custom]) {
      if (seenIds.add(ex.id)) allExercises.add(ex);
    }

    final muscleGroups  = _service.getMuscleGroups();
    final equipmentList = _service.getEquipmentList();
    final categories    = _service.getCategories();
    final difficulties  = _service.getDifficultyList();

    final filtered = _service.filterExercises(
      exercises: allExercises,
      category:   _selectedCategory,
      muscleGroup: _selectedMuscle,
      equipment:  _selectedEquipment,
      difficulty: _selectedDifficulty,
      search:     _search,
    );

    final isLoading = myAsync.isLoading || globalAsync.isLoading;
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    final isStaff = role == 'coach' || role == 'admin';

    return AppScaffold(
      showBackButton: true,
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset('assets/images/background.png',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.65),
            colorBlendMode: BlendMode.darken,
            errorBuilder: (_, __, ___) => Container(color: _C.bg))),

        Column(children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Exercise Database',
                  style: TextStyle(color: _C.onSurface, fontSize: 24,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const Spacer(),
                // Coach/admin: bulk-resolve in-app videos for the whole catalog.
                if (isStaff)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: _enriching ? null : _runVideoEnrichment,
                      child: _enriching
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: _C.tertiary, strokeWidth: 2))
                        : const Icon(Icons.video_library_outlined, color: _C.tertiary, size: 22))),
                if (isLoading)
                  const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2)),
                if (!isLoading && custom.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.primaryContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _C.primaryContainer.withValues(alpha: 0.3))),
                    child: Text('+${custom.length} custom',
                      style: const TextStyle(color: _C.primaryContainer, fontSize: 10,
                        fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 10),

              // Search
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(Icons.search, color: _C.outline.withValues(alpha: 0.7), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _C.onSurface, fontSize: 13),
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        hintText: 'Search name, muscle, tag…',
                        hintStyle: TextStyle(color: _C.outline, fontSize: 13),
                        border: InputBorder.none, isDense: true,
                        contentPadding: EdgeInsets.zero))),
                  if (_search.isNotEmpty)
                    GestureDetector(
                      onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(Icons.close, color: _C.outline.withValues(alpha: 0.6), size: 16))),
                ])),
              const SizedBox(height: 8),

              // Filter row 1: Category + Difficulty
              Row(children: [
                Expanded(child: _DropdownFilter(
                  label: 'Category',
                  value: _selectedCategory,
                  options: categories,
                  activeColor: _C.tertiary,
                  onChanged: (v) => setState(() => _selectedCategory = v ?? 'All'))),
                const SizedBox(width: 8),
                Expanded(child: _DropdownFilter(
                  label: 'Difficulty',
                  value: _selectedDifficulty,
                  options: difficulties,
                  activeColor: _C.amber,
                  onChanged: (v) => setState(() => _selectedDifficulty = v ?? 'All'))),
              ]),
              const SizedBox(height: 8),

              // Filter row 2: Muscle + Equipment
              Row(children: [
                Expanded(child: _DropdownFilter(
                  label: 'Muscle',
                  value: _selectedMuscle,
                  options: muscleGroups,
                  activeColor: _C.primary,
                  onChanged: (v) => setState(() => _selectedMuscle = v ?? 'All'))),
                const SizedBox(width: 8),
                Expanded(child: _DropdownFilter(
                  label: 'Equipment',
                  value: _selectedEquipment,
                  options: equipmentList,
                  activeColor: _C.secondary,
                  onChanged: (v) => setState(() => _selectedEquipment = v ?? 'All'))),
              ]),
              const SizedBox(height: 8),

              // Result count + clear filters
              Row(children: [
                Text('${filtered.length} exercise${filtered.length == 1 ? '' : 's'}',
                  style: TextStyle(color: _C.onSurfaceVar.withValues(alpha: 0.55), fontSize: 11)),
                const Spacer(),
                if (_hasActiveFilter)
                  GestureDetector(
                    onTap: _clearFilters,
                    child: const Text('Clear filters',
                      style: TextStyle(color: _C.primary, fontSize: 11,
                        fontWeight: FontWeight.w700))),
              ]),
            ])),

          // ── Grid ──────────────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.fitness_center,
                        color: _C.outline.withValues(alpha: 0.3), size: 48),
                      const SizedBox(height: 12),
                      Text('No exercises found',
                        style: TextStyle(
                          color: _C.onSurfaceVar.withValues(alpha: 0.5), fontSize: 15)),
                      if (_hasActiveFilter) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filters', style: TextStyle(color: _C.primary))),
                      ]
                    ]))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 12,
                      mainAxisSpacing: 12, childAspectRatio: 0.60),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ExerciseCard(
                      exercise: filtered[i],
                      onTap: () {
                        ref.read(selectedExerciseDetailProvider.notifier).state = filtered[i];
                        context.push('/exercise-detail');
                      }))),
        ]),

        // Coach: create a new exercise (with form video, instructions, etc.).
        if ((ref.watch(currentUserProfileProvider).valueOrNull?['role']) == 'coach')
          Positioned(
            right: 20, bottom: 24,
            child: GestureDetector(
              onTap: () => context.push('/create-exercise'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_C.primaryContainer, _C.primary]),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [BoxShadow(color: _C.primaryContainer.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))]),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text('New Exercise', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ]))),
          ),
      ]),
    );
  }

  bool get _hasActiveFilter =>
      _selectedCategory != 'All' ||
      _selectedMuscle   != 'All' ||
      _selectedEquipment!= 'All' ||
      _selectedDifficulty != 'All' ||
      _search.isNotEmpty;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _search             = '';
      _selectedCategory   = 'All';
      _selectedMuscle     = 'All';
      _selectedEquipment  = 'All';
      _selectedDifficulty = 'All';
    });
  }
}

// ── Dropdown Filter ───────────────────────────────────────────────────────────
class _DropdownFilter extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final Color activeColor;
  final ValueChanged<String?> onChanged;
  const _DropdownFilter({
    required this.label, required this.value,
    required this.options, required this.activeColor,
    required this.onChanged});

  bool get _active => value != 'All';

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    height: 40,
    decoration: BoxDecoration(
      color: _active
          ? activeColor.withValues(alpha: 0.12)
          : _C.surfaceContainerMax.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: _active
            ? activeColor.withValues(alpha: 0.4)
            : _C.outlineVar.withValues(alpha: 0.3))),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: _C.surfaceContainerHigh,
        style: TextStyle(color: _active ? activeColor : _C.onSurface, fontSize: 11,
          fontWeight: _active ? FontWeight.w700 : FontWeight.w400),
        icon: Icon(Icons.keyboard_arrow_down,
          color: _active ? activeColor : _C.outline, size: 16),
        items: options.map((o) => DropdownMenuItem(value: o,
          child: Text(o, style: TextStyle(
            color: o == value ? activeColor : _C.onSurface,
            fontSize: 11,
            fontWeight: o == value ? FontWeight.w700 : FontWeight.w400)))).toList(),
        onChanged: onChanged)));
}

// ── Image helper ──────────────────────────────────────────────────────────────
Widget _exerciseImg(ExerciseDetail ex) {
  if (ex.imageAssetPath != null) {
    return Image.asset(ex.imageAssetPath!, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _NoImage());
  }
  if (ex.imageUrl != null) {
    return CachedNetworkImage(
      imageUrl: ex.imageUrl!, fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const _NoImage(),
      placeholder: (_, __) => const _NoImage());
  }
  return const _NoImage();
}

// ── Exercise Card ─────────────────────────────────────────────────────────────
class _ExerciseCard extends StatelessWidget {
  final ExerciseDetail exercise;
  final VoidCallback onTap;
  const _ExerciseCard({required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final levelColor = _levelColor(exercise.difficulty);
    final isCustom = exercise.coachId != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _C.glassCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isCustom
              ? _C.primaryContainer.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05))),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              _exerciseImg(exercise),
              // Gradient overlay
              const DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xCC0E0E0F)],
                  stops: [0.5, 1.0],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter))),
              // Top badges
              Positioned(top: 8, left: 8, right: 8,
                child: Row(children: [
                  _Badge(
                    label: exercise.difficulty.substring(0, 3).toUpperCase(),
                    color: levelColor),
                  const SizedBox(width: 4),
                  _Badge(
                    label: exercise.category.substring(0, 3).toUpperCase(),
                    color: _C.tertiary),
                  const Spacer(),
                  if (isCustom)
                    _Badge(label: 'MINE', color: _C.primaryContainer),
                ])),
            ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exercise.name,
                style: const TextStyle(color: _C.onSurface, fontSize: 13,
                  fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Container(width: 5, height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _C.primary)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('${exercise.muscleGroup} · ${exercise.equipment}',
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 9,
                      fontWeight: FontWeight.w500, letterSpacing: 0.3),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ])),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF842BD2), Color(0xFFB76DFF)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Text('VIEW DETAILS',
                style: TextStyle(color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5)))),
        ])));
  }

  Color _levelColor(String d) {
    switch (d.toLowerCase()) {
      case 'beginner':     return _C.secondary;
      case 'advanced':     return _C.tertiary;
      case 'elite':        return _C.primary;
      default:             return _C.onSurfaceVar;
    }
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Text(label, style: TextStyle(color: color, fontSize: 8,
      fontWeight: FontWeight.w700, letterSpacing: 0.5)));
}

class _NoImage extends StatelessWidget {
  const _NoImage();
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF201F20),
    child: const Center(
      child: Icon(Icons.fitness_center_outlined,
        color: Color(0xFF4B444F), size: 32)));
}
