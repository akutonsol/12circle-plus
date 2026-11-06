import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/coach/presentation/program_builder_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The Programs list and the Assign sheet both read `myProgramsProvider`, and the
// sheet refuses a program whose day count is 0. That count comes from one query,
// and the provider keeps its answer for the life of the app. Saving a workout
// refreshed only the builder's own list, so a coach who had just built a week saw
// it greyed out as "No training days yet" until they pulled to refresh. Deleting a
// program's last day was the same defect the other way round: the empty program
// stayed selectable. Creating and deleting a whole program refreshed the list only
// while the coach stayed put: a coach who tapped away before the answer came back
// hit a disposed `ref`, and the list kept its old answer.
//
// These drive the real screens. Only the service is substituted, through the two
// list providers, which still respond to invalidation.

const _clientId = 'client-1';
const _noDays = 'No training days yet — add workouts in Programs before assigning';
const _program = 'Week One';

class _FakeSvc extends Fake implements CoachProgramService {
  final programs = <Map<String, dynamic>>[];
  final workouts = <Map<String, dynamic>>[];
  final assigned = <String>[];

  /// When set, a workout write waits on this, so a test can act mid-save.
  Completer<void>? writeGate;

  /// The same for the insert of a new program and for a program's deletion.
  Completer<void>? createGate;
  Completer<void>? deleteGate;

  var _nextId = 0;
  String _id(String prefix) => '$prefix-${_nextId++}';

  void seedProgram(String id, String name, {List<String> days = const []}) {
    programs.add({'id': id, 'name': name, 'goal': 'Goal', 'duration_weeks': 8});
    for (final day in days) {
      workouts.add({
        'id': _id('workout'),
        'program_id': id,
        'title': 'Session',
        'week_number': 1,
        'day_of_week': day,
        'exercises': const <Map<String, dynamic>>[],
      });
    }
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
    await createGate?.future;
    final row = {...data, 'id': _id('program')};
    programs.add(row);
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> getProgramWorkouts(String programId) async =>
      workouts.where((w) => w['program_id'] == programId).toList();

  @override
  Future<void> addWorkoutToProgram(
      String programId, Map<String, dynamic> workout) async {
    await writeGate?.future;
    workouts.add({...workout, 'id': _id('workout'), 'program_id': programId});
  }

  @override
  Future<void> updateWorkout(String workoutId, Map<String, dynamic> data) async {
    await writeGate?.future;
    final row = workouts.firstWhere((w) => w['id'] == workoutId);
    row.addAll(data);
  }

  @override
  Future<void> deleteWorkout(String workoutId) async {
    await writeGate?.future;
    workouts.removeWhere((w) => w['id'] == workoutId);
  }

  @override
  Future<void> deleteProgram(String programId) async {
    await deleteGate?.future;
    programs.removeWhere((p) => p['id'] == programId);
    workouts.removeWhere((w) => w['program_id'] == programId);
  }

  @override
  Future<void> assignProgram(String programId, String clientId) async =>
      assigned.add('$programId>$clientId');
}

/// Answers every request with an empty list, so nothing can reach a real service.
class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
        headers: {'content-type': 'application/json'},
      );
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// Client detail runs repeating animations, so `pumpAndSettle` would not return.
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

  // The same shape as the coach's app: the bottom nav swaps these two inside a
  // shell, which takes the builder off screen along with the list.
  final router = GoRouter(
    initialLocation: '/programs',
    routes: [
      ShellRoute(
        builder: (_, __, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/programs',
            builder: (_, __) => const ProgramLibraryScreen(),
          ),
          GoRoute(
            path: '/client',
            builder: (_, __) =>
                const ClientDetailScreen(clientId: _clientId, clientName: 'Jordan'),
          ),
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
      clientDetailProvider(_clientId).overrideWith((ref) async => {
            'id': _clientId,
            'first_name': 'Jordan',
            'last_name': 'Test',
            'role': 'client',
          }),
      clientHasPaidPlanProvider(_clientId).overrideWith((ref) async => true),
      clientScheduleProvider(_clientId).overrideWith((ref) async => null),
      clientScoreProvider(_clientId).overrideWith((ref) async => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(t);
  return router;
}

Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

Future<void> _createProgram(WidgetTester t, String name) async {
  await t.tap(find.text('New Program'));
  await _settle(t);
  await t.enterText(_field('e.g. 12-Week Hypertrophy'), name);
  await t.tap(find.text('Create & build'));
  await _settle(t);
}

Future<void> _pickDay(WidgetTester t, String from, String to) async {
  await t.tap(find.text(from));
  await _settle(t);
  await t.tap(find.text(to).last);
  await _settle(t);
}

Future<void> _addWednesdayWorkout(WidgetTester t) async {
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
}

Future<void> _openBuilder(WidgetTester t, String name) async {
  await t.tap(find.text(name));
  await _settle(t);
}

/// From inside a program's builder: the program's own menu, then the confirm.
Future<void> _deleteProgramFromMenu(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.more_vert));
  await _settle(t);
  await t.tap(find.text('Delete program'));
  await _settle(t);
  await t.tap(find.text('Delete'));
  await _settle(t);
}

Future<void> _openAssignSheet(WidgetTester t, GoRouter router) async {
  router.go('/client');
  await _settle(t);
  final open = find.text('Assign / Change Program');
  await t.ensureVisible(open);
  await _settle(t);
  await t.tap(open);
  await _settle(t);
}

void _expectListCount(String name, int count) {
  final card = find.ancestor(of: find.text(name), matching: find.byType(InkWell));
  expect(
    find.descendant(of: card, matching: find.textContaining('$count workouts')),
    findsOneWidget,
    reason: '$name should list $count workouts',
  );
}

ElevatedButton _assignButton(WidgetTester t) => t.widget<ElevatedButton>(
    find.ancestor(
        of: find.text('Assign Program'), matching: find.byType(ElevatedButton)));

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      // Unroutable, so the client detail screen's other reads cannot touch QA.
      url: 'http://127.0.0.1:1',
      anonKey: 'test-anon-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  group('adding a workout', () {
    testWidgets('leaving by the nav bar: the program can be assigned at once',
        (t) async {
      final svc = _FakeSvc()..seedProgram('existing', 'Existing Plan', days: ['Monday']);
      final router = await _pump(t, svc);

      await _createProgram(t, _program);
      await _addWednesdayWorkout(t);

      // The Wednesday day is what was saved, and what the builder shows.
      expect(find.textContaining('Wednesday'), findsOneWidget);
      final saved = svc.workouts.last;
      expect(saved['day_of_week'], 'Wednesday');
      expect(saved['sort_order'], 2);

      await _openAssignSheet(t, router);

      expect(find.text(_noDays), findsNothing);
      await t.tap(find.text(_program));
      await _settle(t);
      expect(_assignButton(t).onPressed, isNotNull);

      await t.tap(find.text('Assign Program'));
      await _settle(t);
      expect(svc.assigned, ['${saved['program_id']}>$_clientId']);
    });

    testWidgets('leaving by the back arrow: the list shows the new count', (t) async {
      final svc = _FakeSvc()
        ..seedProgram('existing', 'Existing Plan', days: ['Monday', 'Friday']);
      await _pump(t, svc);

      await _createProgram(t, _program);
      await _addWednesdayWorkout(t);
      await t.tap(find.byType(BackButton));
      await _settle(t);

      _expectListCount(_program, 1);
      _expectListCount('Existing Plan', 2);
    });

    testWidgets('leaving while the save is still in flight: the count still updates',
        (t) async {
      final svc = _FakeSvc()..writeGate = Completer<void>();
      final router = await _pump(t, svc);

      await _createProgram(t, _program);
      await _addWednesdayWorkout(t);

      // The coach taps away before the insert has answered.
      router.go('/client');
      await _settle(t);
      svc.writeGate!.complete();
      await _settle(t);

      expect(svc.workouts, hasLength(1));
      router.go('/programs');
      await _settle(t);
      _expectListCount(_program, 1);
    });
  });

  group('changing a saved workout', () {
    testWidgets('deleting the last day: the program stops being assignable',
        (t) async {
      final svc = _FakeSvc()..seedProgram('p1', _program, days: ['Wednesday']);
      final router = await _pump(t, svc);
      _expectListCount(_program, 1);

      await _openBuilder(t, _program);
      await t.tap(find.byIcon(Icons.more_horiz));
      await _settle(t);
      await t.tap(find.text('Delete'));
      await _settle(t);
      expect(find.textContaining('No workouts yet'), findsOneWidget);

      await _openAssignSheet(t, router);

      expect(find.text(_noDays), findsOneWidget);
      await t.tap(find.text(_program));
      await _settle(t);
      expect(_assignButton(t).onPressed, isNull,
          reason: 'an empty program must not reach a client');
    });

    testWidgets('deleting one of two days: the count drops and it stays assignable',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday', 'Friday']);
      final router = await _pump(t, svc);
      _expectListCount(_program, 2);

      await _openBuilder(t, _program);
      await t.tap(find.byIcon(Icons.more_horiz).first);
      await _settle(t);
      await t.tap(find.text('Delete'));
      await _settle(t);
      await t.tap(find.byType(BackButton));
      await _settle(t);
      _expectListCount(_program, 1);

      await _openAssignSheet(t, router);
      expect(find.text(_noDays), findsNothing);
    });

    testWidgets('moving a day to Friday: shown at once, and still assignable',
        (t) async {
      final svc = _FakeSvc()..seedProgram('p1', _program, days: ['Wednesday']);
      final router = await _pump(t, svc);

      await _openBuilder(t, _program);
      await t.tap(find.byIcon(Icons.more_horiz));
      await _settle(t);
      await t.tap(find.text('Edit'));
      await _settle(t);
      await _pickDay(t, 'Wednesday', 'Friday');
      await t.tap(find.text('Save workout'));
      await _settle(t);

      expect(find.textContaining('Friday'), findsOneWidget);
      expect(find.textContaining('Wednesday'), findsNothing);

      await _openAssignSheet(t, router);
      expect(find.text(_noDays), findsNothing);
      await t.tap(find.text(_program));
      await _settle(t);
      expect(_assignButton(t).onPressed, isNotNull);
    });
  });

  group('leaving while the write is still in flight', () {
    testWidgets('deleting: the count still updates', (t) async {
      final svc = _FakeSvc()..seedProgram('p1', _program, days: ['Wednesday']);
      final router = await _pump(t, svc);

      await _openBuilder(t, _program);
      svc.writeGate = Completer<void>();
      await t.tap(find.byIcon(Icons.more_horiz));
      await _settle(t);
      await t.tap(find.text('Delete'));
      await _settle(t);

      router.go('/client');
      await _settle(t);
      svc.writeGate!.complete();
      await _settle(t);

      expect(svc.workouts, isEmpty);
      router.go('/programs');
      await _settle(t);
      _expectListCount(_program, 0);
    });

    testWidgets('editing: the write finishes without an error', (t) async {
      final svc = _FakeSvc()..seedProgram('p1', _program, days: ['Wednesday']);
      final router = await _pump(t, svc);

      await _openBuilder(t, _program);
      svc.writeGate = Completer<void>();
      await t.tap(find.byIcon(Icons.more_horiz));
      await _settle(t);
      await t.tap(find.text('Edit'));
      await _settle(t);
      await _pickDay(t, 'Wednesday', 'Friday');
      await t.tap(find.text('Save workout'));
      await _settle(t);

      router.go('/client');
      await _settle(t);
      svc.writeGate!.complete();
      await _settle(t);

      expect(svc.workouts.single['day_of_week'], 'Friday');
    });
  });

  group('creating a program', () {
    testWidgets('leaving before the insert finishes: the program is still listed',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('existing', 'Existing Plan', days: ['Monday'])
        ..createGate = Completer<void>();
      final router = await _pump(t, svc);

      await _createProgram(t, _program);

      // The coach taps away before the insert has answered.
      router.go('/client');
      await _settle(t);
      svc.createGate!.complete();
      await _settle(t);

      expect(svc.programs.map((p) => p['name']), contains(_program));
      router.go('/programs');
      await _settle(t);
      _expectListCount(_program, 0);
      _expectListCount('Existing Plan', 1);
    });

    testWidgets('the same from an empty list: it is not left on "No programs yet"',
        (t) async {
      final svc = _FakeSvc()..createGate = Completer<void>();
      final router = await _pump(t, svc);
      expect(find.textContaining('No programs yet'), findsOneWidget);

      await _createProgram(t, _program);
      router.go('/client');
      await _settle(t);
      svc.createGate!.complete();
      await _settle(t);

      router.go('/programs');
      await _settle(t);
      expect(find.textContaining('No programs yet'), findsNothing);
      _expectListCount(_program, 0);
    });
  });

  group('deleting a program', () {
    testWidgets('from the menu: gone from the list and from the Assign sheet',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..seedProgram('p2', 'Other Plan', days: ['Monday']);
      final router = await _pump(t, svc);

      await _openBuilder(t, _program);
      await _deleteProgramFromMenu(t);

      expect(svc.programs.map((p) => p['id']), ['p2']);
      expect(find.text(_program), findsNothing);
      _expectListCount('Other Plan', 1);

      await _openAssignSheet(t, router);
      expect(find.text(_program), findsNothing);
      expect(find.text('Other Plan'), findsOneWidget);
    });

    testWidgets('leaving while the delete is in flight: the list still drops it',
        (t) async {
      final svc = _FakeSvc()
        ..seedProgram('p1', _program, days: ['Wednesday'])
        ..seedProgram('p2', 'Other Plan', days: ['Monday']);
      final router = await _pump(t, svc);

      await _openBuilder(t, _program);
      svc.deleteGate = Completer<void>();
      await _deleteProgramFromMenu(t);

      router.go('/client');
      await _settle(t);
      svc.deleteGate!.complete();
      await _settle(t);

      expect(svc.programs.map((p) => p['id']), ['p2']);
      router.go('/programs');
      await _settle(t);
      expect(find.text(_program), findsNothing);
      _expectListCount('Other Plan', 1);
    });
  });

  testWidgets('a program that really has no days is still refused', (t) async {
    final svc = _FakeSvc()..seedProgram('p1', _program);
    final router = await _pump(t, svc);

    await _openAssignSheet(t, router);

    expect(find.text(_noDays), findsOneWidget);
    await t.tap(find.text(_program));
    await _settle(t);
    expect(_assignButton(t).onPressed, isNull);
  });
}
