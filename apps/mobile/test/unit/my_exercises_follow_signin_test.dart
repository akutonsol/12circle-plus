import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_member_postgrest.dart';

// P0-FL-57a (b) · a coach's own exercises, and the exercise they opened to
// edit, belong to the coach signed in NOW.
//
// `myExercisesNotifierProvider` loaded once for the app's lifetime: after a
// switch it kept A's list, and A's late load, create or delete landed under B.
// `editingExerciseProvider` still held A's exercise id, so B's "create" opened
// as an edit of A's exercise.
//
// Every transition is a REAL one on the Supabase auth stream, through the real
// `currentUserProvider` and the real service.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- apps/mobile/lib/features/
// exercise_database/domain/custom_exercise_provider.dart`.

Map<String, Object?> _ex(String id, String coach) =>
    {'id': id, 'name': 'Exercise $id', 'coach_id': coach, 'slug': id};

Map<String, dynamic> _fields() => {
      'name': 'New Move',
      'category': 'Strength',
      'muscle_group': 'Legs',
      'equipment': 'Dumbbell',
      'difficulty': 'Beginner',
    };

void main() {
  late TwoMemberPostgrest server;
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoMemberPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    server.exercises.addAll([
      _ex('a-1', memberA),
      _ex('shared', memberA),
      _ex('b-1', memberB),
      _ex('shared', memberB),
    ]);
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
    c.listen(myExercisesNotifierProvider, (_, __) {});
  });

  tearDown(() async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.dispose();
    resetFailureSink();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));
  AsyncValue<List<ExerciseDetail>> state() =>
      c.read(myExercisesNotifierProvider);
  MyExercisesNotifier notifier() =>
      c.read(myExercisesNotifierProvider.notifier);
  List<String>? ids() => state().hasValue
      ? [for (final e in state().requireValue) e.id]
      : null;

  Future<void> asA() async {
    await settle();
    expect(ids(), ['a-1', 'shared'], reason: "premise: A's own list");
  }

  group('the list', () {
    test("B's read pending: nothing of A; then B's own list", () async {
      await asA();
      final hold =
          server.holds['GET custom_exercises:$memberB'] = Completer<void>();
      await signInAs(memberB);
      await settle();
      expect(ids(), isNull, reason: "THE defect: A's exercises shown to B");
      expect(state().isLoading, isTrue);
      hold.complete();
      await settle();
      expect(ids(), ['b-1', 'shared']);
    });

    test("B's read fails: an error, recorded, and nothing of A", () async {
      await asA();
      server.fails.add('GET custom_exercises:$memberB');
      await signInAs(memberB);
      await settle();
      expect(ids(), isNull, reason: "THE defect: A's exercises shown to B");
      expect(state().hasError, isTrue);
      expect(reported.map((f) => f.origin), ['MyExercisesNotifier.load']);
    });

    test("sign-out drops the list; signing in again loads that coach's",
        () async {
      await asA();
      await signOut();
      await settle();
      expect(ids(), anyOf(isNull, isEmpty),
          reason: "THE defect: A's list outlived sign-out");
      await signInAs(memberB);
      await settle();
      expect(ids(), ['b-1', 'shared']);
    });

    test("A's held load landing after B signs in is dropped", () async {
      await asA();
      final holdA =
          server.holds['GET custom_exercises:$memberA'] = Completer<void>();
      final holdB =
          server.holds['GET custom_exercises:$memberB'] = Completer<void>();
      unawaited(notifier().refresh());
      await settle();
      await signInAs(memberB);
      await settle();
      holdA.complete();
      await settle();
      expect(ids(), isNull, reason: "THE defect: A's late load landed under B");
      holdB.complete();
      await settle();
      expect(ids(), ['b-1', 'shared']);
    });

    test("A's held load failing after B signs in does not fail B's list",
        () async {
      await asA();
      final holdA =
          server.holds['GET custom_exercises:$memberA'] = Completer<void>();
      server.fails.add('GET custom_exercises:$memberA');
      unawaited(notifier().refresh());
      await settle();
      await signInAs(memberB);
      await settle();
      holdA.complete();
      await settle();
      expect(ids(), ['b-1', 'shared']);
      expect(state().hasError, isFalse);
    });

    test("A's delete completing after B signs in leaves B's list alone",
        () async {
      await asA();
      final hold =
          server.holds['DELETE custom_exercises:$memberA'] = Completer<void>();
      final done = notifier().delete('shared');
      await settle();
      server.exercises.add(_ex('shared', memberB));
      await signInAs(memberB);
      await settle();
      expect(ids(), ['b-1', 'shared']);
      hold.complete();
      expect(await done, isTrue);
      await settle();
      expect(ids(), ['b-1', 'shared'],
          reason: "THE defect: A's delete dropped a row from B's list");
    });

    final writes = {
      'create': (MyExercisesNotifier n) => n.create(fields: _fields()),
      'submitForGlobal': (MyExercisesNotifier n) => n.submitForGlobal('a-1'),
    };
    for (final w in writes.entries) {
      test("A's ${w.key} completing after B signs in does not touch B's list",
          () async {
        await asA();
        final verb = w.key == 'create' ? 'POST' : 'PATCH';
        final hold = server.holds['$verb custom_exercises:$memberA'] =
            Completer<void>();
        final Future<Object?> done = w.value(notifier());
        await settle();
        expect(server.calls, contains('$verb custom_exercises:$memberA'));
        await signInAs(memberB);
        await settle();
        final reads = server.calls.length;
        expect(ids(), ['b-1', 'shared']);
        hold.complete();
        expect(await done, w.key == 'create' ? 'ex-new' : isTrue);
        await settle();
        expect(ids(), ['b-1', 'shared']);
        expect(server.calls.length, reads,
            reason: "A's finished write must not reload anything as B");
      });
    }

    test('an older load landing after a newer one does not replace it',
        () async {
      await asA();
      final older =
          server.holds['GET custom_exercises:$memberA'] = Completer<void>();
      unawaited(notifier().refresh());
      await settle();
      server.holds.clear();
      server.exercises.add(_ex('a-2', memberA));
      await notifier().refresh();
      expect(ids(), ['a-1', 'shared', 'a-2']);
      older.complete();
      await settle();
      expect(ids(), ['a-1', 'shared', 'a-2'],
          reason: 'THE defect: the older answer replaced the newer one');
    });

    test('a row deleted while a load is in flight does not come back',
        () async {
      await asA();
      final older =
          server.holds['GET custom_exercises:$memberA'] = Completer<void>();
      unawaited(notifier().refresh());
      await settle();
      server.holds.clear();
      expect(await notifier().delete('a-1'), isTrue);
      expect(ids(), ['shared']);
      older.complete();
      await settle();
      expect(ids(), ['shared'],
          reason: 'THE defect: the load that started first brought it back');
    });

    test("a failed refresh keeps the coach's list, beside the error", () async {
      await asA();
      server.fails.add('GET custom_exercises:$memberA');
      await notifier().refresh();
      expect(ids(), ['a-1', 'shared'], reason: 'THE defect: the list was lost');
      expect(state().hasError, isTrue);
      // A delete then is shown, and the failed refresh is still said.
      expect(await notifier().delete('a-1'), isTrue);
      expect(ids(), ['shared']);
      expect(state().hasError, isTrue);
      // …and a refresh that works clears it.
      server.fails.clear();
      await notifier().refresh();
      expect(ids(), ['shared']);
      expect(state().hasError, isFalse);
    });

    test("positive control: the same coach's refresh, create and delete",
        () async {
      await asA();
      server.exercises.add(_ex('a-2', memberA));
      await notifier().refresh();
      expect(ids(), ['a-1', 'shared', 'a-2']);
      expect(await notifier().create(fields: _fields()), 'ex-new');
      expect(ids(), ['a-1', 'shared', 'a-2', 'ex-new']);
      expect(await notifier().delete('a-2'), isTrue);
      expect(ids(), ['a-1', 'shared', 'ex-new']);
      expect(reported, isEmpty);
    });

    test('control: a session refresh is the same coach — no reload, kept',
        () async {
      await asA();
      final reads = server.calls.length;
      final n = notifier();
      await refreshSession();
      await settle();
      expect(identical(notifier(), n), isTrue);
      expect(server.calls.length, reads);
      expect(ids(), ['a-1', 'shared']);
    });

    test('negative control: a coach with no exercises has an empty list',
        () async {
      await asA();
      server.exercises.removeWhere((e) => e['coach_id'] == memberB);
      await signInAs(memberB);
      await settle();
      expect(ids(), isEmpty);
      expect(state().hasError, isFalse);
      expect(reported, isEmpty);
    });
  });

  group('the exercise opened to edit', () {
    test('is not handed to the next coach, nor kept through sign-out',
        () async {
      await asA();
      c.read(editingExerciseProvider.notifier).state = 'a-1';
      await signInAs(memberB);
      await settle();
      expect(c.read(editingExerciseProvider), isNull,
          reason:
              "THE defect: B's create form opened as an edit of A's exercise");
      c.read(editingExerciseProvider.notifier).state = 'b-1';
      await signOut();
      await settle();
      expect(c.read(editingExerciseProvider), isNull);
    });

    test('control: is kept for the same coach through a session refresh',
        () async {
      await asA();
      c.read(editingExerciseProvider.notifier).state = 'a-1';
      await refreshSession();
      await settle();
      expect(c.read(editingExerciseProvider), 'a-1');
    });
  });
}
