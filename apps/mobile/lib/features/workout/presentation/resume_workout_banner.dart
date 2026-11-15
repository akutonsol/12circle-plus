import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/workout_session_store.dart';
import '../domain/workout_provider.dart';

// ── UC10: Resume Incomplete Workout Banner ────────────────────────────────────
// Drop this widget anywhere in the home/train hub screen to show the prompt
// when a user has an in-progress workout session.
//
// Reads the same `activeSessionProvider` the Train hub uses, so both surfaces
// always name the same session, and resumes through the same binding helper so
// the Workout Zone opens on that session's workout rather than on whatever was
// last selected in memory.

class ResumeWorkoutBanner extends ConsumerStatefulWidget {
  const ResumeWorkoutBanner({super.key});
  @override
  ConsumerState<ResumeWorkoutBanner> createState() => _ResumeWorkoutBannerState();
}

class _ResumeWorkoutBannerState extends ConsumerState<ResumeWorkoutBanner> {
  bool _dismissed = false;
  bool _discarding = false;

  /// Discards the in-progress session -- and hides the banner only once the
  /// server has it. It used to hide first and swallow a failed abandon: the
  /// session stayed in_progress (and a user may hold only one, so it blocked
  /// the next workout) while the banner said it was gone.
  Future<void> _dismiss(WorkoutSessionRecord session) async {
    if (_discarding) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _discarding = true);
    try {
      await ref.read(workoutSessionManagerProvider).abandonSession(session.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _discarding = false);
      messenger?.showSnackBar(const SnackBar(
          content: Text("Couldn't discard the workout. It's still in progress — try again.")));
      return;
    }
    if (!mounted) return;
    setState(() {
      _discarding = false;
      _dismissed = true;
    });
    ref.invalidate(activeSessionProvider);
  }

  Future<void> _resume(WorkoutSessionRecord session) async {
    final workout = await bindSessionToSelectedWorkout(ref, session);
    if (!mounted) return;
    if (workout == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That workout is no longer available.')));
      return;
    }
    context.push('/active-workout');
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final session = ref.watch(activeSessionProvider).valueOrNull;
    if (session == null) return const SizedBox.shrink();

    final elapsed = DateTime.now().difference(session.startedAt);
    final mins = elapsed.inMinutes;
    final workoutName =
        session.workoutTitle.isNotEmpty ? session.workoutTitle : 'Workout';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0F2E), Color(0xFF0F1A0F)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: const Color(0xFFA855F7).withValues(alpha: 0.15), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFA855F7).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.fitness_center_rounded, color: Color(0xFFA855F7), size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Resume Workout?',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('$workoutName • $mins min elapsed',
            style: const TextStyle(color: Color(0xFFCFC2D6), fontSize: 12)),
        ])),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => _resume(session),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFA855F7),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            // The theme's minimumSize is full-width, which a Row cannot give.
            minimumSize: const Size(0, 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => _dismiss(session),
          icon: const Icon(Icons.close_rounded, color: Color(0xFFCFC2D6), size: 18),
          padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }
}
