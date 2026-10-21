import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/exercise_database_provider.dart';
import '../domain/custom_exercise_provider.dart';
import '../data/custom_exercise_service.dart';
import '../data/models/exercise_detail_model.dart';
import '../../workout/data/models/video_variant_model.dart';
import '../../workout/presentation/widgets/youtube_embed.dart';
import '../../auth/domain/auth_provider.dart';
import 'widgets/coach_focus_section.dart';
import '../../../core/widgets/named_icon_button.dart';

class _C {
  static const bg                   = Color(0xFF0E0E0F);
  static const surfaceContainerHigh = Color(0xFF2A2A2B);
  static const primary              = Color(0xFFDDB7FF);
  static const inversePrimary       = Color(0xFF842BD2);
  static const onSurface            = Color(0xFFE5E2E3);
  static const onSurfaceVar         = Color(0xFFCDC3D0);
  static const outline              = Color(0xFF968E99);
  static const outlineVar           = Color(0xFF4B444F);
  static const tertiary             = Color(0xFF6FFBBE);
  static const error                = Color(0xFFFFB4AB);
  static const warning              = Color(0xFFF59E0B);
}

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer an exercise passed via route `extra` (e.g. tapping an alternative)
    // so the back stack keeps each detail's own exercise; fall back to the
    // shared provider for the library's existing navigation.
    final extra = GoRouterState.of(context).extra;
    final exercise = extra is ExerciseDetail
        ? extra : ref.watch(selectedExerciseDetailProvider);
    if (exercise == null) {
      return Scaffold(
        backgroundColor: _C.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.fitness_center, color: _C.primary, size: 48),
            const SizedBox(height: 16),
            const Text('No exercise selected',
              style: TextStyle(color: _C.onSurface, fontSize: 16)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.canPop() ? context.pop() : context.go('/train'),
              child: const Text('Back to Library',
                style: TextStyle(color: _C.primary))),
          ]),
        ),
      );
    }
    return _ExerciseDetailView(exercise: exercise);
  }
}

class _ExerciseDetailView extends StatelessWidget {
  final ExerciseDetail exercise;
  const _ExerciseDetailView({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final levelColor = _levelColor(exercise.difficulty);

    return Scaffold(
      backgroundColor: _C.bg,
      extendBodyBehindAppBar: true,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _EditFab(exercise: exercise),
          const SizedBox(height: 12),
          _EnrichFab(exercise: exercise),
        ]),
      body: CustomScrollView(slivers: [

        // ── Hero App Bar ──────────────────────────────────────────────────────
        SliverAppBar(
          backgroundColor: Colors.transparent,
          expandedHeight: 300,
          pinned: true,
          leading: NamedIconButton(
            label: 'Back',
            onTap: () => context.canPop()
                ? context.pop()
                : context.go('/exercise-library'),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
              child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18))),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              _heroImage(exercise),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0xCC0E0E0F), Color(0xFF0E0E0F)],
                    stops: [0.3, 0.75, 1.0],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter))),
              Positioned(
                bottom: 20, left: 20,
                child: Row(children: [
                  _Tag(label: exercise.muscleGroup.toUpperCase()),
                  const SizedBox(width: 8),
                  _Tag(label: exercise.difficulty.toUpperCase(), color: levelColor),
                  const SizedBox(width: 8),
                  _Tag(label: exercise.equipment),
                ])),
            ])),
        ),

        // ── Content ───────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Name + description
              Text(exercise.name,
                style: const TextStyle(color: _C.onSurface, fontSize: 28,
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(exercise.description,
                style: const TextStyle(color: _C.onSurfaceVar, fontSize: 14, height: 1.5)),
              const SizedBox(height: 20),

              // Coach overlay (layered media Phase 1): coach adds their focus /
              // note / video; the client sees their coach's version here.
              CoachFocusSection(exerciseId: exercise.id,
                matchText: '${exercise.name} ${exercise.muscleGroup} ${exercise.equipment}'),

              // Stats chips
              Row(children: [
                Expanded(child: _StatChip(icon: Icons.sports_gymnastics_outlined,
                  label: 'EQUIPMENT', value: exercise.equipment)),
                const SizedBox(width: 10),
                Expanded(child: _StatChip(icon: Icons.signal_cellular_alt_outlined,
                  label: 'DIFFICULTY', value: exercise.difficulty)),
                const SizedBox(width: 10),
                Expanded(child: _StatChip(icon: Icons.adjust_outlined,
                  label: 'MUSCLE', value: exercise.muscleGroup)),
              ]),
              const SizedBox(height: 24),

              // Tags
              if (exercise.tags.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6,
                  children: exercise.tags.map((t) => _TagChip(label: t)).toList()),
                const SizedBox(height: 24),
              ],

              // Video variants (multi-video with label chips)
              if (exercise.videoVariants.isNotEmpty) ...[
                const _SectionTitle(title: 'Video Tutorials',
                  icon: Icons.play_circle_outline_rounded, iconColor: _C.primary),
                const SizedBox(height: 12),
                ...exercise.videoVariants.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VideoVariantCard(variant: v))),
                const SizedBox(height: 14),
              ] else if (exercise.videoUrl != null) ...[
                _VideoVariantCard(variant: VideoVariant(
                  url: exercise.videoUrl!,
                  label: 'Tutorial',
                  type: VideoVariant.detectType(exercise.videoUrl!))),
                const SizedBox(height: 24),
              ] else ...[
                // No uploaded video yet — offer a tutorial search.
                _FindVideoCard(query: '${exercise.name} proper form technique'),
                const SizedBox(height: 24),
              ],

              // Secondary muscles
              if (exercise.secondaryMuscles.isNotEmpty) ...[
                const _SectionTitle(title: 'Secondary Muscles'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8,
                  children: exercise.secondaryMuscles
                      .map((m) => _MuscleChip(label: m)).toList()),
                const SizedBox(height: 24),
              ],

              // Instructions
              const _SectionTitle(title: 'Instructions',
                icon: Icons.list_outlined, iconColor: _C.primary),
              const SizedBox(height: 12),
              ..._numberedList(exercise.instructions, _C.primary),
              const SizedBox(height: 24),

              // Coaching cues
              if (exercise.coachingCues.isNotEmpty) ...[
                const _SectionTitle(title: 'Coaching Cues',
                  icon: Icons.tips_and_updates_outlined, iconColor: _C.warning),
                const SizedBox(height: 12),
                ..._numberedList(exercise.coachingCues, _C.warning),
                const SizedBox(height: 24),
              ],

              // Common mistakes
              if (exercise.commonMistakes.isNotEmpty) ...[
                const _SectionTitle(title: 'Common Mistakes',
                  icon: Icons.warning_amber_outlined, iconColor: _C.error),
                const SizedBox(height: 12),
                ..._numberedList(exercise.commonMistakes, _C.error),
                const SizedBox(height: 24),
              ],

              // Beginner modification
              if (exercise.beginnerModification != null) ...[
                _ModCard(icon: Icons.accessibility_new, title: 'Beginner Modification',
                  color: _C.tertiary, text: exercise.beginnerModification!),
                const SizedBox(height: 12),
              ],

              // Advanced progression
              if (exercise.advancedProgression != null) ...[
                _ModCard(icon: Icons.trending_up, title: 'Advanced Progression',
                  color: _C.primary, text: exercise.advancedProgression!),
                const SizedBox(height: 24),
              ],

              // Alternatives
              if (exercise.alternatives.isNotEmpty) ...[
                const _SectionTitle(title: 'Alternatives'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8,
                  children: exercise.alternatives.map((a) => _AltChip(label: a)).toList()),
              ],
            ]),
          )),
      ]),
    );
  }

  Widget _heroImage(ExerciseDetail ex) {
    if (ex.imageAssetPath != null) {
      return Image.asset(ex.imageAssetPath!, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _gradientHero(ex.muscleGroup));
    }
    if (ex.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: ex.imageUrl!, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _gradientHero(ex.muscleGroup),
        placeholder: (_, __) => _gradientHero(ex.muscleGroup));
    }
    return _gradientHero(ex.muscleGroup);
  }

  Color _levelColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'beginner': return const Color(0xFFADC6FF);
      case 'advanced': return _C.tertiary;
      case 'elite': return _C.primary;
      default: return _C.onSurfaceVar;
    }
  }

  Widget _gradientHero(String muscleGroup) {
    final colors = {
      'Chest': [const Color(0xFF2A1A4E), _C.bg],
      'Back': [const Color(0xFF0B2E1A), _C.bg],
      'Legs': [const Color(0xFF1A2E0B), _C.bg],
      'Core': [const Color(0xFF2E1A0B), _C.bg],
      'Shoulders': [const Color(0xFF0B1A2E), _C.bg],
    };
    final pair = colors[muscleGroup] ?? [const Color(0xFF1A1A2E), _C.bg];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: pair, begin: Alignment.topLeft, end: Alignment.bottomRight)));
  }

  List<Widget> _numberedList(List<String> items, Color color) {
    return items.asMap().entries.map((e) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text('${e.key + 1}',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(child: Text(e.value,
          style: const TextStyle(color: _C.onSurfaceVar, fontSize: 14, height: 1.5))),
      ]),
    )).toList();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
class _VideoVariantCard extends StatelessWidget {
  final VideoVariant variant;
  const _VideoVariantCard({required this.variant});

  String _normalizeUrl(String url) {
    // Convert Vimeo embed/player URLs to web URLs
    final vimeoMatch = RegExp(r'vimeo\.com/(?:video/)?(\d+)').firstMatch(url);
    if (vimeoMatch != null) return 'https://vimeo.com/${vimeoMatch.group(1)}';
    return url;
  }

  (IconData, Color, String) get _meta {
    if (variant.isYoutube) return (Icons.smart_display_rounded, const Color(0xFFFF0000), 'YouTube');
    if (variant.isVimeo)   return (Icons.play_circle_fill_rounded, const Color(0xFF1AB7EA), 'Vimeo');
    return (Icons.videocam_rounded, _C.primary, 'Video');
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, platform) = _meta;
    return GestureDetector(
      onTap: () => _openVideoLightbox(context, _normalizeUrl(variant.url), variant.label),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A0D2E), Color(0xFF0F0B1A)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(variant.label.toUpperCase(),
              style: const TextStyle(color: _C.primary, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 3),
            Text('Tap to play · $platform',
              style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12, height: 1.3)),
          ])),
          Icon(Icons.play_circle_fill_rounded, color: color, size: 24),
        ])));
  }
}

/// In-app lightbox player. Uses the web embed (YouTube/Vimeo iframe or native
/// <video>); falls back to an external launch where the embed isn't available.
void _openVideoLightbox(BuildContext context, String url, String label) {
  final player = buildInAppVideo(url);
  if (player == null) {
    final uri = Uri.parse(url);
    canLaunchUrl(uri).then((ok) {
      if (ok) launchUrl(uri, mode: LaunchMode.externalApplication);
    });
    return;
  }
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (dctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(label.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w800, letterSpacing: 1.2))),
          IconButton(
            onPressed: () => Navigator.of(dctx).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(aspectRatio: 16 / 9, child: player)),
      ]),
    ),
  );
}

// Shown when an exercise has no uploaded video — opens a YouTube tutorial search.
class _FindVideoCard extends StatelessWidget {
  final String query;
  const _FindVideoCard({required this.query});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      final uri = Uri.parse(
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
      canLaunchUrl(uri).then((ok) {
        if (ok) launchUrl(uri, mode: LaunchMode.externalApplication);
      });
    },
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.outlineVar.withValues(alpha: 0.25))),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFFF0000).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.smart_display_rounded, color: Color(0xFFFF0000), size: 26)),
        const SizedBox(width: 14),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FIND A FORM VIDEO', style: TextStyle(color: _C.primary, fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          SizedBox(height: 3),
          Text('Search tutorials on YouTube', style: TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
        ])),
        const Icon(Icons.open_in_new, color: _C.onSurfaceVar, size: 15),
      ])));
}

// Coach/admin-only: open the create screen in edit mode for this exercise.
class _EditFab extends ConsumerWidget {
  final ExerciseDetail exercise;
  const _EditFab({required this.exercise});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    if (role != 'coach' && role != 'admin') return const SizedBox.shrink();
    return FloatingActionButton.extended(
      heroTag: 'ex-edit',
      backgroundColor: _C.surfaceContainerHigh,
      onPressed: () {
        ref.read(editingExerciseProvider.notifier).state = exercise.id;
        context.push('/create-exercise');
      },
      icon: const Icon(Icons.edit_outlined, color: _C.onSurface, size: 20),
      label: const Text('Edit', style: TextStyle(color: _C.onSurface, fontWeight: FontWeight.w700)),
    );
  }
}

// Coach/admin-only FAB: generate coaching content with AI, then reload.
class _EnrichFab extends ConsumerStatefulWidget {
  final ExerciseDetail exercise;
  const _EnrichFab({required this.exercise});
  @override
  ConsumerState<_EnrichFab> createState() => _EnrichFabState();
}

class _EnrichFabState extends ConsumerState<_EnrichFab> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    // AI generation is admin-only; coaches add media via Edit instead.
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    if (role != 'admin') return const SizedBox.shrink();

    final hasContent = widget.exercise.instructions.isNotEmpty;
    return FloatingActionButton.extended(
      heroTag: 'ex-enrich',
      backgroundColor: _C.inversePrimary,
      onPressed: _loading ? null : _enrich,
      icon: _loading
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.auto_awesome, color: Colors.white),
      label: Text(
        _loading ? 'Generating…' : (hasContent ? 'Regenerate with AI' : 'Enrich with AI'),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _enrich() async {
    setState(() => _loading = true);
    final svc = ref.read(customExerciseSvcProvider);
    // Slug-less (legacy manual) exercises: derive + assign one first.
    var slug = widget.exercise.slug;
    if (slug == null || slug.isEmpty) {
      slug = CustomExerciseService.slugify(widget.exercise.name);
      await svc.updateExercise(widget.exercise.id, {'slug': slug});
    }
    final res = await svc.enrichWithAI(slug);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Enrichment failed')));
      return;
    }
    final updated = await svc.getExerciseBySlug(slug);
    ref.invalidate(globalApprovedExercisesProvider);
    ref.invalidate(myExercisesProvider);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coaching content generated ✨')));
    if (updated != null) {
      ref.read(selectedExerciseDetailProvider.notifier).state = updated;
      context.pushReplacement('/exercise-detail', extra: updated);
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Text(label,
        style: TextStyle(color: c, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 1)));
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _C.inversePrimary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _C.primary.withValues(alpha: 0.2))),
    child: Text(label,
      style: const TextStyle(color: _C.primary, fontSize: 11,
        fontWeight: FontWeight.w600)));
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: _C.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _C.outlineVar.withValues(alpha: 0.2))),
    child: Column(children: [
      Icon(icon, color: _C.primary, size: 18),
      const SizedBox(height: 4),
      Text(label,
        style: const TextStyle(color: _C.outline, fontSize: 8,
          fontWeight: FontWeight.w600, letterSpacing: 1)),
      const SizedBox(height: 2),
      Text(value,
        style: const TextStyle(color: _C.onSurface, fontSize: 11,
          fontWeight: FontWeight.w700),
        textAlign: TextAlign.center),
    ]));
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  const _SectionTitle({required this.title, this.icon, this.iconColor});
  @override
  Widget build(BuildContext context) => Row(children: [
    if (icon != null) ...[
      Icon(icon, color: iconColor, size: 18),
      const SizedBox(width: 8),
    ],
    Text(title, style: const TextStyle(color: _C.onSurface, fontSize: 16,
      fontWeight: FontWeight.w700)),
  ]);
}

class _MuscleChip extends StatelessWidget {
  final String label;
  const _MuscleChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: _C.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3))),
    child: Text(label, style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12)));
}

class _AltChip extends ConsumerWidget {
  final String label;
  const _AltChip({required this.label});

  ExerciseDetail? _match(List<ExerciseDetail> all) {
    final q = label.toLowerCase().trim();
    for (final e in all) {
      if (e.name.toLowerCase().trim() == q) return e;
    }
    for (final e in all) {
      if (e.name.toLowerCase().contains(q)) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = _match(ref.watch(allExercisesProvider));
    final linked = match != null;
    return GestureDetector(
      onTap: linked
          ? () {
              ref.read(selectedExerciseDetailProvider.notifier).state = match;
              context.push('/exercise-detail', extra: match);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: linked ? _C.inversePrimary.withValues(alpha: 0.12) : _C.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: linked
              ? _C.primary.withValues(alpha: 0.4)
              : _C.outlineVar.withValues(alpha: 0.2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            color: linked ? _C.primary : _C.onSurfaceVar, fontSize: 13,
            fontWeight: linked ? FontWeight.w600 : FontWeight.w400)),
          if (linked) ...[
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, color: _C.primary, size: 14),
          ],
        ])),
    );
  }
}

class _ModCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String text;
  const _ModCard({required this.icon, required this.title,
    required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontSize: 12,
          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: _C.onSurfaceVar,
          fontSize: 13, height: 1.5)),
      ])),
    ]));
}
