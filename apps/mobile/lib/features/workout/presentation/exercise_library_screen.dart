import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../exercise_database/domain/exercise_database_provider.dart';
import '../../exercise_database/domain/custom_exercise_provider.dart';
import '../../exercise_database/data/exercise_database_service.dart';
import '../../exercise_database/data/models/exercise_detail_model.dart';

class _C {
  static const bg                   = Color(0xFF0E0E0F);
  static const surfaceContainerHigh = Color(0xFF2A2A2B);
  static const glassCard            = Color(0x99201F20);
  static const primary              = Color(0xFFDDB7FF);
  static const onSurface            = Color(0xFFE5E2E3);
  static const onSurfaceVar         = Color(0xFFCDC3D0);
  static const outline              = Color(0xFF968E99);
  static const outlineVar           = Color(0xFF4B444F);
  static const tertiary             = Color(0xFF6FFBBE);
  static const secondary            = Color(0xFFADC6FF);
}

const _tabs = ['ALL', 'CHEST', 'BACK', 'LEGS', 'CORE', 'SHOULDERS', 'ARMS', 'CARDIO', 'MOBILITY'];

// Muscle groups that belong under each tab (lowercased).
const _tabMuscles = <String, List<String>>{
  'CHEST': ['chest', 'upper chest', 'lower chest', 'serratus'],
  'BACK': ['back', 'lats', 'mid back', 'upper back', 'lower back', 'traps', 'lower traps'],
  'LEGS': ['legs', 'quadriceps', 'hamstrings', 'glutes', 'calves', 'adductors',
    'abductors', 'hip flexors', 'tibialis', 'it band'],
  'CORE': ['core', 'abs', 'obliques'],
  'SHOULDERS': ['shoulders', 'front delts', 'side delts', 'rear delts', 'rotator cuff'],
  'ARMS': ['arms', 'biceps', 'triceps', 'forearms', 'grip'],
};

bool _matchesTab(ExerciseDetail e, String tab) {
  if (tab == 'CARDIO') {
    final c = e.category.toLowerCase();
    return c.contains('cardio') || c.contains('conditioning');
  }
  if (tab == 'MOBILITY') {
    final c = e.category.toLowerCase();
    return c.contains('mobility') || c.contains('recovery') || c.contains('stretch');
  }
  final muscles = _tabMuscles[tab] ?? const [];
  final mg = e.muscleGroup.toLowerCase();
  if (muscles.contains(mg)) return true;
  return e.secondaryMuscles.any((s) => muscles.contains(s.toLowerCase()));
}

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});
  @override
  ConsumerState<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  int _activeTab = 0;
  String _search = '';
  final _searchCtrl = TextEditingController();
  final _service = ExerciseDatabaseService();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static library + global-approved custom exercises (so coach-published
    // exercises show up for clients). Dedup by id.
    final builtIn = _service.getAllExercises();
    final globalCustom =
        ref.watch(globalApprovedExercisesProvider).whenOrNull(data: (d) => d) ?? [];
    final seen = <String>{};
    final allExercises = <ExerciseDetail>[];
    for (final ex in [...globalCustom, ...builtIn]) {
      if (seen.add(ex.id)) allExercises.add(ex);
    }
    // Search first, then filter by tab using a muscle-group→tab map so seeded
    // exercises (muscleGroup "Quadriceps", "Lats", …) land under the right tab.
    final searched = _service.filterExercises(
      exercises: allExercises, muscleGroup: 'All', search: _search);
    final tab = _tabs[_activeTab];
    final filtered = tab == 'ALL'
        ? searched
        : searched.where((e) => _matchesTab(e, tab)).toList();

    return AppScaffold(
      showBackButton: true,
      body: Column(children: [

        // ── Search + tabs ──────────────────────────────────────────────────
        Container(
          color: _C.bg,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(children: [
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: _C.surfaceContainerHigh.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.outlineVar.withValues(alpha: 0.2))),
              child: Row(children: [
                const SizedBox(width: 14),
                Icon(Icons.search, color: _C.outline, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: _C.onSurface, fontSize: 14),
                    onChanged: (v) => setState(() => _search = v),
                    decoration: const InputDecoration(
                      hintText: 'Search exercises...',
                      hintStyle: TextStyle(color: _C.outline, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero))),
              ])),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final active = i == _activeTab;
                  return GestureDetector(
                    onTap: () => setState(() => _activeTab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        color: active
                            ? _C.primary.withValues(alpha: 0.15)
                            : _C.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active
                              ? _C.primary.withValues(alpha: 0.5)
                              : _C.outlineVar.withValues(alpha: 0.2))),
                      alignment: Alignment.center,
                      child: Text(_tabs[i],
                        style: TextStyle(
                          color: active ? _C.primary : _C.onSurfaceVar,
                          fontSize: 11,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          letterSpacing: 1))));
                })),
            const SizedBox(height: 16),
          ])),

        // ── Exercise list ──────────────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fitness_center, color: _C.outline.withValues(alpha: 0.3), size: 48),
                    const SizedBox(height: 12),
                    Text('No exercises found',
                      style: TextStyle(color: _C.onSurfaceVar.withValues(alpha: 0.5), fontSize: 15)),
                  ]))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final ex = filtered[i];
                    return GestureDetector(
                      onTap: () {
                        ref.read(selectedExerciseDetailProvider.notifier).state = ex;
                        context.push('/exercise-detail');
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _C.glassCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x0DFFFFFF))),
                        clipBehavior: Clip.antiAlias,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Image area
                          SizedBox(
                            height: 180,
                            child: Stack(fit: StackFit.expand, children: [
                              _exerciseImage(ex),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Color(0x88000000)],
                                    begin: Alignment.topCenter, end: Alignment.bottomCenter))),
                              Positioned(
                                bottom: 12, left: 12,
                                child: Row(children: [
                                  _Tag(label: ex.muscleGroup.toUpperCase()),
                                  const SizedBox(width: 6),
                                  _Tag(label: ex.difficulty.toUpperCase(),
                                    color: _levelColor(ex.difficulty)),
                                ])),
                            ])),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(ex.name,
                                style: const TextStyle(color: _C.onSurface, fontSize: 18,
                                  fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                              const SizedBox(height: 6),
                              Text(ex.description,
                                style: const TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.4),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 10),
                              Row(children: [
                                Icon(Icons.sports_gymnastics_outlined, color: _C.primary, size: 14),
                                const SizedBox(width: 4),
                                Text(ex.equipment,
                                  style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                                const SizedBox(width: 16),
                                Icon(Icons.chevron_right, color: _C.outline, size: 16),
                                Text('View Details',
                                  style: TextStyle(color: _C.primary.withValues(alpha: 0.7), fontSize: 12)),
                              ]),
                            ])),
                        ])));
                  })),
      ]),
    );
  }

  Widget _exerciseImage(ExerciseDetail ex) {
    if (ex.imageAssetPath != null) {
      return Image.asset(ex.imageAssetPath!, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _gradientCard(ex.muscleGroup));
    }
    if (ex.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: ex.imageUrl!, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _gradientCard(ex.muscleGroup),
        placeholder: (_, __) => _gradientCard(ex.muscleGroup));
    }
    return _gradientCard(ex.muscleGroup);
  }

  Color _levelColor(String d) {
    switch (d.toLowerCase()) {
      case 'beginner': return _C.secondary;
      case 'advanced': return _C.tertiary;
      case 'elite': return _C.primary;
      default: return _C.onSurfaceVar;
    }
  }

  Widget _gradientCard(String muscle) {
    final colors = {
      'Chest': [const Color(0xFF2A1A4E), const Color(0xFF1A0A30)],
      'Back': [const Color(0xFF0B2E1A), const Color(0xFF061508)],
      'Quads': [const Color(0xFF1A2E0B), const Color(0xFF0A1806)],
      'Glutes': [const Color(0xFF2E1A0B), const Color(0xFF180D06)],
      'Hamstrings': [const Color(0xFF1A150B), const Color(0xFF0A0806)],
      'Core': [const Color(0xFF1A0B2E), const Color(0xFF0D0618)],
      'Shoulders': [const Color(0xFF0B1A2E), const Color(0xFF060D18)],
    };
    final pair = colors[muscle] ?? [const Color(0xFF1A1A2E), const Color(0xFF0A0A18)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: pair,
          begin: Alignment.topLeft, end: Alignment.bottomRight)));
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  const _Tag({required this.label, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? _C.onSurfaceVar;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Text(label, style: TextStyle(color: c, fontSize: 9,
        fontWeight: FontWeight.w700, letterSpacing: 1)));
  }
}
