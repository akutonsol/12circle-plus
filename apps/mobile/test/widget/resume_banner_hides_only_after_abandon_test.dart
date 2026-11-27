import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';
import 'package:circle_fitness/features/workout/presentation/resume_workout_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The Resume Workout banner's close button hid the banner FIRST and swallowed a
// failed abandon. The session stayed in_progress on the server -- and a user may
// hold only one (workout_sessions_one_active_per_user), so it blocked the next
// workout -- while the banner said it was gone. It now hides only when the
// abandon succeeded, and says so when it did not.
//
// HOW TO SEE IT FAIL: on main the banner disappears although the abandon threw.

class _Manager extends Fake implements WorkoutSessionManager {
  _Manager({required this.fails});
  final bool fails;
  int calls = 0;
  @override
  Future<void> abandonSession(String sessionId) async {
    calls++;
    if (fails) throw Exception('offline');
  }
}

final _session = WorkoutSessionRecord(
  id: 's-1', userId: 'u-1', workoutId: 'w-1', workoutTitle: 'Lower Body',
  status: 'in_progress', startedAt: DateTime.now().subtract(const Duration(minutes: 12)));

Future<_Manager> _pump(WidgetTester t, {required bool fails}) async {
  final m = _Manager(fails: fails);
  await t.pumpWidget(ProviderScope(
    overrides: [
      // Whose session it is: the signed-in member's (P0-FL-59b).
      restoringUserIdProvider.overrideWithValue('u-1'),
      activeSessionProvider.overrideWith((ref) async => _session),
      workoutSessionManagerProvider.overrideWithValue(m),
    ],
    child: const MaterialApp(home: Scaffold(body: ResumeWorkoutBanner())),
  ));
  await t.pumpAndSettle();
  expect(find.text('Resume Workout?'), findsOneWidget);
  await t.tap(find.byIcon(Icons.close_rounded));
  await t.pumpAndSettle();
  return m;
}

void main() {
  testWidgets('a failed discard keeps the banner and says so', (t) async {
    final m = await _pump(t, fails: true);
    expect(m.calls, 1);
    expect(find.text('Resume Workout?'), findsOneWidget,
        reason: 'THE defect: the banner hid although the session is still in progress');
    expect(find.textContaining("Couldn't discard"), findsOneWidget);
  });

  testWidgets('a discard that worked hides the banner (positive control)', (t) async {
    final m = await _pump(t, fails: false);
    expect(m.calls, 1);
    expect(find.text('Resume Workout?'), findsNothing);
  });
}
