import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/presentation/program_builder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Every write in the program builder (create or delete a program, add, edit or
// delete a workout) was awaited with no handler. A failure, whether no network, a
// refused row or a foreign key, escaped as an unhandled error: the coach was told
// nothing, and could not tell a save that failed from one that worked.
//
// Deleting a program that has ever been assigned is refused by the database (a
// foreign key, Postgres 23503). The delete dialog used to say assigned clients
// "keep their copy", which is not what happens.
//
// These drive the real screens. Only the service is substituted, and it throws.

const _program = 'Week One';
const _deleteFailed = "Couldn't delete the program — check your connection and try again.";
const _deleteBlocked =
    "This program can't be deleted because clients are or have been assigned to it.";
const _createFailed = "Couldn't create the program — check your connection and try again.";
const _workoutSaveFailed = "Couldn't save the workout — check your connection and try again.";
const _workoutDeleteFailed =
    "Couldn't delete the workout — check your connection and try again.";

final _foreignKey = PostgrestException(
  message: 'update or delete on table "workout_programs" violates foreign key '
      'constraint "workout_program_assignments_program_id_fkey"',
  code: '23503',
);

class _FakeSvc extends Fake implements CoachProgramService {
  final programs = <Map<String, dynamic>>[];
  final workouts = <Map<String, dynamic>>[];

  /// Method name -> what it throws. Absent means it succeeds.
  final failures = <String, Object>{};

  /// When set, `deleteProgram` waits on this, so a test can leave mid-delete.
  Completer<void>? deleteGate;

  var _nextId = 0;

  void seedProgram(String id, String name, {List<String> days = const []}) {
    programs.add({'id': id, 'name': name, 'goal': 'Goal', 'duration_weeks': 8});
    for (final day in days) {
      workouts.add({
        'id': 'workout-${_nextId++}',
        'program_id': id,
        'title': 'Session',
        'week_number': 1,
        'day_of_week': day,
        'exercises': const <Map<String, dynamic>>[],
      });
    }
  }

  void _maybeFail(String method) {
    final error = failures[method];
    if (error != null) throw error;
  }

  @override
  Future<List<Map<String, dynamic>>> getMyPrograms() async => [
        for (final p in programs)
          {
            ...p,
            'program_workouts': [
              {'count': workouts.where((w) => w['program_id'] == p['id']).length},
            ],
          },
      ];

  @override
  Future<Map<String, dynamic>> createProgram(Map<String, dynamic> data) async {
    _maybeFail('createProgram');
    final row = {...data, 'id': 'program-${_nextId++}'};
    programs.add(row);
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> getProgramWorkouts(String programId) async =>
      workouts.where((w) => w['program_id'] == programId).toList();

  @override
  Future<void> addWorkoutToProgram(
      String programId, Map<String, dynamic> workout) async {
    _maybeFail('addWorkoutToProgram');
    workouts.add({...workout, 'id': 'workout-${_nextId++}', 'program_id': programId});
  }

  @override
  Future<void> updateWorkout(String workoutId, Map<String, dynamic> data) async {
    _maybeFail('updateWorkout');
    workouts.firstWhere((w) => w['id'] == workoutId).addAll(data);
  }

  @override
  Future<void> deleteWorkout(String workoutId) async {
    _maybeFail('deleteWorkout');
    workouts.removeWhere((w) => w['id'] == workoutId);
  }

  @override
  Future<void> deleteProgram(String programId) async {
    await deleteGate?.future;
    _maybeFail('deleteProgram');
    programs.removeWhere((p) => p['id'] == programId);
    workouts.removeWhere((w) => w['program_id'] == programId);
  }
}

/// The builder runs no repeating animation, but the shell does not settle under
/// `pumpAndSettle` once a SnackBar timer is pending.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<GoRouter> _pump(WidgetTester t, _FakeSvc svc) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 4000);
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/programs',
    routes: [
      ShellRoute(
        builder: (_, __, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/programs', builder: (_, __) => const ProgramLibraryScreen()),
          GoRoute(path: '/elsewhere', builder: (_, __) => const Text('elsewhere')),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      coachProgramServiceProvider.overrideWithValue(svc),
      myProgramsProvider.overrideWith((ref) => svc.getMyPrograms()),
      programWorkoutsProvider
          .overrideWith((ref, programId) => svc.getProgramWorkouts(programId)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(t);
  return router;
}

Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

Future<void> _openBuilder(WidgetTester t) async {
  await t.tap(find.text(_program));
  await _settle(t);
}

Future<void> _pickDay(WidgetTester t, String from, String to) async {
  await t.tap(find.text(from));
  await _settle(t);
  await t.tap(find.text(to).last);
  await _settle(t);
}

Future<void> _deleteProgramFromMenu(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.more_vert));
  await _settle(t);
  await t.tap(find.text('Delete program'));
  await _settle(t);
  await t.tap(find.text('Delete'));
  await _settle(t);
}

void main() {
  late List<AppFailure> reported;

  setUp(() {
    reported = [];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
  });

  group('creating a program', () {
    testWidgets('a failed insert is reported and said, and nothing is opened',
        (t) async {
      final svc = _FakeSvc()..failures['createProgram'] = Exception('offline');
      await _pump(t, svc);

      await t.tap(find.text('New Program'));
      await _settle(t);
      await t.enterText(_field('e.g. 12-Week Hypertrophy'), _program);
      await t.tap(find.text('Create & build'));
      await _settle(t);

      expect(find.text(_createFailed), findsOneWidget);
      expect(find.textContaining('No programs yet'), findsOneWidget);
      expect(find.textContaining('No workouts yet'), findsNothing,
          reason: 'the builder must not open for a program that was not saved');
      expect(reported, hasLength(1));
    });
  });

  group('workouts', () {
    testWidgets('a failed add is reported and said, and nothing is added', (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Monday'])
        ..failures['addWorkoutToProgram'] = Exception('offline');
      await _pump(t, svc);
      await _openBuilder(t);

      await t.tap(find.text('Add Workout'));
      await _settle(t);
      await t.enterText(_field('e.g. Upper Body Push'), 'Full Body');
      await _pickDay(t, 'Monday', 'Wednesday');
      await t.tap(find.text('Add').last);
      await _settle(t);
      await t.enterText(_field('e.g. Bench Press'), 'Push Up');
      await t.tap(find.text('Add').last);
      await _settle(t);
      await t.tap(find.text('Save workout'));
      await _settle(t);

      expect(find.text(_workoutSaveFailed), findsOneWidget);
      expect(svc.workouts, hasLength(1));
      expect(reported, hasLength(1));
    });

    testWidgets('a failed edit is reported and said, and the day is unchanged',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..failures['updateWorkout'] = Exception('offline');
      await _pump(t, svc);
      await _openBuilder(t);

      await t.tap(find.byIcon(Icons.more_horiz));
      await _settle(t);
      await t.tap(find.text('Edit'));
      await _settle(t);
      await _pickDay(t, 'Wednesday', 'Friday');
      await t.tap(find.text('Save workout'));
      await _settle(t);

      expect(find.text(_workoutSaveFailed), findsOneWidget);
      expect(svc.workouts.single['day_of_week'], 'Wednesday');
      expect(reported, hasLength(1));
    });

    testWidgets('a failed delete is reported and said, and the day stays',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..failures['deleteWorkout'] = Exception('offline');
      await _pump(t, svc);
      await _openBuilder(t);

      await t.tap(find.byIcon(Icons.more_horiz));
      await _settle(t);
      await t.tap(find.text('Delete'));
      await _settle(t);

      expect(find.text(_workoutDeleteFailed), findsOneWidget);
      expect(svc.workouts, hasLength(1));
      expect(find.textContaining('Wednesday'), findsOneWidget);
      expect(reported, hasLength(1));
    });
  });

  group('deleting a program', () {
    testWidgets('a failure that is not about assignments says to try again',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..failures['deleteProgram'] = Exception('offline');
      await _pump(t, svc);
      await _openBuilder(t);

      await _deleteProgramFromMenu(t);

      expect(find.text(_deleteFailed), findsOneWidget);
      expect(find.text(_deleteBlocked), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget,
          reason: 'the builder stays open: nothing was deleted');
      expect(svc.programs, hasLength(1));
      expect(reported, hasLength(1));
    });

    testWidgets('a program that has been assigned says why it cannot be deleted',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..failures['deleteProgram'] = _foreignKey;
      await _pump(t, svc);
      await _openBuilder(t);

      await _deleteProgramFromMenu(t);

      expect(find.text(_deleteBlocked), findsOneWidget);
      expect(find.text(_deleteFailed), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(svc.programs, hasLength(1));
    });

    testWidgets('the confirmation no longer says assigned clients keep a copy',
        (t) async {
      final svc = _FakeSvc()..seedProgram('p1', _program, days: ['Wednesday']);
      await _pump(t, svc);
      await _openBuilder(t);

      await t.tap(find.byIcon(Icons.more_vert));
      await _settle(t);
      await t.tap(find.text('Delete program'));
      await _settle(t);

      expect(find.text('Delete program?'), findsOneWidget);
      expect(find.textContaining('keep their copy'), findsNothing);
      expect(find.textContaining("can't be deleted"), findsOneWidget);
    });

    testWidgets('a refusal that arrives after the coach has left is still said',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..failures['deleteProgram'] = _foreignKey;
      final router = await _pump(t, svc);
      await _openBuilder(t);
      svc.deleteGate = Completer<void>();
      await _deleteProgramFromMenu(t);

      router.go('/elsewhere');
      await _settle(t);
      svc.deleteGate!.complete();
      await _settle(t);

      expect(find.text('elsewhere'), findsOneWidget);
      expect(find.text(_deleteBlocked), findsOneWidget);
      expect(svc.programs, hasLength(1));
    });
  });
}
