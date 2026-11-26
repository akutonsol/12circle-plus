import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/pump_until.dart';
import '../support/settled.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c (a) · /goals. A failed create/update was swallowed unrecorded, an
// update that changed no row was reported as saved, the progress dialog threw
// away what was typed before it knew, and a goal member A typed could be saved
// as member B's.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` goal_service.dart and
// goals_screen.dart.

const _support =
    'try again in a moment. If it keeps happening, contact support.';
const _network = 'check your connection and try again.';

Map<String, Object?> _goal(String id, String uid, String title) => {
      'id': id, 'client_id': uid, 'title': title, 'type': 'performance',
      'start_value': 80, 'target_value': 100, 'current_value': 90,
      'unit': 'kg', 'status': 'active', 'created_at': '2026-11-01T10:00:00Z',
    };

void main() {
  final server = OwnedRowsPostgrest();
  final reported = <AppFailure>[];
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    server.rows['goals'] = [
      _goal('g-a', memberA, 'Bench 100 kg'),
      _goal('g-b', memberB, 'Row 2k'),
    ];
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
  });

  tearDown(() {
    c.dispose();
    resetFailureSink();
  });

  List<String> origins() => [for (final f in reported) f.origin];
  List<Asked> writes() => server.writes('goals');
  Finder text(String s) => find.text(s);

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: GoalsScreen())));
    await pumpUntil(tester, () => text('Bench 100 kg').evaluate().isNotEmpty,
        what: "A's goals");
  }

  Future<void> settle(WidgetTester tester) => settledFrames(tester, server,
      step: const Duration(milliseconds: 50));

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester
        .runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'the account to change');
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(text(item));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openUpdate(WidgetTester tester, String value) async {
    await choose(tester, 'Update progress');
    await tester.enterText(find.byType(TextField), value);
    await tester.pump();
  }

  Future<void> openNew(WidgetTester tester, String title) async {
    await tester.tap(text('New Goal'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, title);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(text(label));
    await settle(tester);
  }

  group('update progress', () {
    for (final (name, arrange, hint) in <(String, void Function(), String)>[
      ('a refused update', () => server.fails.add('PATCH goals:$memberA'), _support),
      ('an update offline', () => server.offline.add('PATCH goals:$memberA'), _network),
      ('an update that changed NO ROW', () => server.filtered.add('PATCH goals:$memberA'), _support),
    ]) {
      testWidgets('$name is recorded, said, and keeps what was typed',
          (tester) async {
        arrange();
        await show(tester);
        await openUpdate(tester, '95');
        await tap(tester, 'Save');

        expect(writes(), hasLength(1));
        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'THE defect: the dialog closed on an unsaved value');
        expect(find.widgetWithText(TextField, '95'), findsOneWidget);
        expect(text("Couldn't update your goal — $hint"), findsOneWidget);
        expect(origins().where((o) => o == 'GoalService.updateProgress'),
            hasLength(1), reason: 'THE defect: unrecorded / reported as saved');
        expect(find.textContaining('SECRET_TABLE'), findsNothing);

        // The same value, sent again, saves.
        server.fails.clear();
        server.offline.clear();
        server.filtered.clear();
        await tap(tester, 'Save');
        expect(find.byType(AlertDialog), findsNothing);
        expect(server.rows['goals']!.first['current_value'], 95);
        expect(find.textContaining('95 / 100 kg'), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets('a value that is not a number is not dropped in silence',
        (tester) async {
      await show(tester);
      await openUpdate(tester, '72,5');
      await tap(tester, 'Save');
      expect(writes(), isEmpty);
      expect(find.widgetWithText(TextField, '72,5'), findsOneWidget,
          reason: 'THE defect: Save closed the dialog and saved nothing');
      expect(text('Enter a number, like 72.5.'), findsOneWidget);
      await done(tester);
    });

    testWidgets('control: a saved update closes and shows the new value',
        (tester) async {
      await show(tester);
      await openUpdate(tester, '95');
      await tap(tester, 'Save');
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes().single.who, memberA);
      expect(find.textContaining('95 / 100 kg'), findsOneWidget);
      expect(reported, isEmpty);
      await done(tester);
    });

    testWidgets('a held save is sent once, however often Save is tapped',
        (tester) async {
      final hold = server.holds['PATCH goals:$memberA'] = Completer<void>();
      await show(tester);
      await openUpdate(tester, '95');
      await tap(tester, 'Save');
      await tester.tap(text('Saving…'));
      await settle(tester);
      expect(writes(), hasLength(1));
      hold.complete();
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await done(tester);
    });

    testWidgets("A->B with A's dialog open: it goes, and nothing is sent",
        (tester) async {
      await show(tester);
      await openUpdate(tester, '95');
      await become(tester, memberB);
      expect(find.byType(AlertDialog), findsNothing,
          reason: "THE defect: A's value stayed in front of B");
      expect(text('Row 2k'), findsOneWidget);
      expect(text('Bench 100 kg'), findsNothing);
      expect(writes(), isEmpty);
      await done(tester);
    });

    testWidgets("A->B while A's save is in flight: no message to B",
        (tester) async {
      final hold = server.holds['PATCH goals:$memberA'] = Completer<void>();
      server.fails.add('PATCH goals:$memberA');
      await show(tester);
      await openUpdate(tester, '95');
      await tap(tester, 'Save');
      await become(tester, memberB);
      hold.complete();
      await settle(tester);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(origins(), contains('GoalService.updateProgress'));
      expect(writes().map((w) => w.who), [memberA]);
      await done(tester);
    });
  });

  for (final (item, method) in [
    ('Update progress', 'PATCH'),
    ('Mark achieved', 'PATCH'),
    ('Delete', 'DELETE'),
  ]) {
    testWidgets('"$item" in flight when the providers go with the account',
        (tester) async {
      final hold = server.holds['$method goals:$memberA'] = Completer<void>();
      await show(tester);
      if (item == 'Update progress') {
        await openUpdate(tester, '95');
        await tap(tester, 'Save');
      } else {
        await choose(tester, item);
        await settle(tester);
      }
      expect(writes(), hasLength(1), reason: 'premise');
      await tester.runAsync(() => signInAs(memberB));
      await tester.pumpWidget(const SizedBox()); // the app root is rebuilt…
      c.dispose(); // …with a new container
      hold.complete();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(origins().where((o) => o.startsWith('GoalsScreen')), isEmpty);
      await done(tester);
    });
  }

  group('mark achieved / delete', () {
    for (final (item, method, verb) in [
      ('Mark achieved', 'PATCH', 'update'),
      ('Delete', 'DELETE', 'delete'),
    ]) {
      testWidgets('"$item" that changed no row is a failure', (tester) async {
        server.filtered.add('$method goals:$memberA');
        await show(tester);
        await choose(tester, item);
        await settle(tester);
        expect(writes(), hasLength(1));
        expect(text("Couldn't $verb your goal — $_support"), findsOneWidget,
            reason: 'THE defect: no row changed, and nothing was said');
        expect(text('Bench 100 kg'), findsOneWidget);
        expect(reported, isNotEmpty);
        await done(tester);
      });
    }

    testWidgets('control: "Delete" removes it', (tester) async {
      await show(tester);
      await choose(tester, 'Delete');
      await settle(tester);
      expect(text('No goals yet'), findsOneWidget, reason: 'empty stays empty');
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
      await done(tester);
    });
  });

  group('new goal', () {
    for (final (name, arrange, hint) in <(String, void Function(), String)>[
      ('refused', () => server.fails.add('POST goals:$memberA'), _support),
      ('offline', () => server.offline.add('POST goals:$memberA'), _network),
    ]) {
      testWidgets('a create that was $name is recorded, said IN the sheet, and keeps it',
          (tester) async {
        arrange();
        await show(tester);
        await openNew(tester, 'Deadlift 140');
        await tap(tester, 'Create Goal');
        expect(writes(), hasLength(1));
        expect(find.widgetWithText(TextField, 'Deadlift 140'), findsOneWidget);
        expect(text("Couldn't save your goal — $hint"), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(BottomSheet),
                matching: find.textContaining("Couldn't save your goal")),
            findsOneWidget,
            reason: 'a SnackBar is behind the sheet');
        expect(origins(), contains('GoalService.createGoal'),
            reason: 'THE defect: unrecorded');
        server.fails.clear();
        server.offline.clear();
        await tap(tester, 'Create Goal');
        expect(find.byType(BottomSheet), findsNothing);
        expect(text('Deadlift 140'), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets('control: a created goal is stamped with its member',
        (tester) async {
      await show(tester);
      await openNew(tester, 'Deadlift 140');
      await tap(tester, 'Create Goal');
      expect(writes().single.body['client_id'], memberA);
      expect(text('Deadlift 140'), findsOneWidget);
      expect(reported, isEmpty);
      await done(tester);
    });

    testWidgets("A->B with A's sheet open: the draft goes; B writes nothing of it",
        (tester) async {
      await show(tester);
      await openNew(tester, 'Private aim');
      await become(tester, memberB);
      expect(find.byType(BottomSheet), findsNothing,
          reason: "THE defect: A's draft stayed, and Create saved it as B's");
      expect(find.textContaining('Private aim'), findsNothing);
      expect(writes(), isEmpty);
      expect(text('Row 2k'), findsOneWidget);
      await done(tester);
    });

    testWidgets('A->B with no frame in between (a hidden tab): Create sends nothing',
        (tester) async {
      await show(tester);
      await openNew(tester, 'Private aim');
      final create = tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Create Goal'))
          .onPressed!;
      await tester.runAsync(() => signInAs(memberB)); // no pump
      create();
      await settle(tester);
      expect(writes(), isEmpty,
          reason: "THE defect: A's goal was inserted for B");
      final f = reported.where((f) => f.origin == 'GoalService.createGoal');
      expect(f.single.error.toString(), contains('the signed-in account changed'));
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });

    testWidgets('sign-out takes the draft with it', (tester) async {
      await show(tester);
      await openNew(tester, 'Private aim');
      await become(tester, null);
      expect(find.textContaining('Private aim'), findsNothing);
      expect(text('Bench 100 kg'), findsNothing);
      await become(tester, memberA);
      await settle(tester);
      expect(text('Bench 100 kg'), findsOneWidget, reason: 'A, back again');
      expect(find.textContaining('Private aim'), findsNothing);
      expect(writes(), isEmpty);
      await done(tester);
    });

    testWidgets('control: a token refresh keeps the draft, and it still saves',
        (tester) async {
      await show(tester);
      await openNew(tester, 'Deadlift 140');
      final before = c.read(currentUserProvider);
      await tester.runAsync(refreshSession);
      await pumpUntil(
          tester, () => !identical(c.read(currentUserProvider), before),
          what: 'the refreshed session');
      await settle(tester);
      expect(find.widgetWithText(TextField, 'Deadlift 140'), findsOneWidget);
      expect(text('Bench 100 kg'), findsOneWidget);
      await tap(tester, 'Create Goal');
      expect(writes().single.body['client_id'], memberA);
      await done(tester);
    });
  });

  group('the list', () {
    testWidgets('control: a token refresh keeps the dialog working',
        (tester) async {
      await show(tester);
      await openUpdate(tester, '95');
      final before = c.read(currentUserProvider);
      final hold = server.holds['GET goals:$memberA'] = Completer<void>();
      await tester.runAsync(refreshSession);
      await pumpUntil(
          tester, () => !identical(c.read(currentUserProvider), before),
          what: 'the refreshed session');
      await settle(tester);
      expect(text('Bench 100 kg'), findsOneWidget,
          reason: 'THE defect: the list blinked away on a refresh');
      server.holds.clear();
      hold.complete();
      await tap(tester, 'Save');
      expect(tester.takeException(), isNull);
      expect(server.rows['goals']!.first['current_value'], 95);
      await done(tester);
    });

    testWidgets('a failed refresh keeps the goals and says so', (tester) async {
      await show(tester);
      server.fails.add('GET goals:$memberA');
      await openUpdate(tester, '95');
      await tap(tester, 'Save'); // saved; the read that follows fails
      expect(text('Bench 100 kg'), findsOneWidget,
          reason: 'THE defect: the goals were replaced by a failure');
      expect(text("Couldn't load your latest goals"), findsOneWidget);
      server.fails.clear();
      await tap(tester, 'Try again');
      expect(find.textContaining('95 / 100 kg'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });

    testWidgets("B's read pending, then failed: nothing of A", (tester) async {
      await show(tester);
      final hold = server.holds['GET goals:$memberB'] = Completer<void>();
      server.fails.add('GET goals:$memberB');
      await become(tester, memberB);
      expect(text('Bench 100 kg'), findsNothing);
      hold.complete();
      await settle(tester);
      expect(text('Bench 100 kg'), findsNothing);
      expect(text("Couldn't load your goals"), findsOneWidget);
      await done(tester);
    });

    testWidgets("A's held read landing after B's is dropped", (tester) async {
      await show(tester);
      final hold = server.holds['GET goals:$memberA'] = Completer<void>();
      await tester.runAsync(refreshSession);
      await settle(tester);
      await become(tester, memberB);
      hold.complete();
      await settle(tester);
      expect(text('Row 2k'), findsOneWidget);
      expect(text('Bench 100 kg'), findsNothing);
      await done(tester);
    });
  });
}
