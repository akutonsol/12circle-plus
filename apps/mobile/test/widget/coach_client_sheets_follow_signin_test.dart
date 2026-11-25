import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/action_items/presentation/assign_action_item_sheet.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach_notes/presentation/coach_notes_sheet.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/vendor/presentation/vendor_portal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

// P0-FL-59f · the page about ONE client, and the sheets opened from it, across
// a real coach A -> coach B switch with everything left mounted.
//
//   * the page: A's client's PAR-Q, score, schedule and paid plan stayed up for
//     B, with no `assessment_access_log` row naming B (the read is logged for
//     whoever asks, and nobody asked);
//   * the sheets: prefilled or typed by A, saved by B.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features`.

const _client = 'cl-1';
const _rpc = 'POST rpc/get_client_assessment';

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    server
      ..seed('user_profiles', memberA, [
        {'id': _client, 'first_name': 'Alma', 'last_name': 'Stone'}
      ])
      ..seed('rpc/get_client_assessment', memberA, [
        {
          'client_id': _client,
          'has_assessment': true,
          'risk_level': 'high',
          'fitness_goal': 'lose_fat',
        }
      ])
      ..seed('subscriptions', memberA, [
        {'id': 's-1'}
      ])
      ..seed('client_schedules', memberA, [
        {
          'client_id': _client,
          'days': ['monday'],
          'session_time': '06:45',
        }
      ])
      ..seed('user_scores', memberA, [
        {
          'user_id': _client,
          'current_cycle_score': 4321,
          'lifetime_score': 98765,
          'level': 7,
          'rank': 'Gold'
        }
      ])
      ..seed('workout_programs', memberA, [
        {'id': 'prog-a', 'name': 'Plan of A', 'duration_weeks': 8, 'goal': ''}
      ])
      ..seed('client_nutrition_plans', memberA, [
        {
          'client_id': _client,
          'calories_target': 1777,
          'protein_g': 141,
          'carbs_g': 171,
          'fat_g': 61,
          'notes': 'secret of A',
        }
      ])
      ..seed('client_habits', memberA, [
        {
          'name': 'Steps',
          'emoji': 'x',
          'unit': 'steps',
          'target_value': 7654,
        }
      ])
      ..seed('coach_notes', memberA, [
        {
          'id': 'note-a',
          'client_id': _client,
          'body': 'private about Alma',
          'tag': 'general',
          'created_at': '2026-11-01T00:00:00Z',
        }
      ]);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> host(WidgetTester tester, Widget home) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 4600);
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(currentUserProvider, (_, __) {});
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp(home: home)));
    await frames(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'signed in: $uid');
    await frames(tester, 2);
  }

  Future<void> tokenRefreshed(WidgetTester tester) async {
    final before = c.read(currentUserProvider);
    await tester.runAsync(refreshSession);
    await pumpUntil(tester, () => c.read(currentUserProvider) != before,
        what: 'the same coach as a new User');
    await frames(tester);
  }

  // ── the page ──────────────────────────────────────────────────────────────

  Future<void> page(WidgetTester tester) async {
    await host(tester,
        const ClientDetailScreen(clientId: _client, clientName: 'Alma Stone'));
    await pumpUntil(tester,
        () => seen(find.text('4321')) && seen(find.text('06:45')) &&
            seen(find.text('HIGH RISK')) &&
            seen(find.text('Assign / Change Program')),
        what: "A's client page");
    await frames(tester);
    server.calls.clear();
  }

  void nothingOfThePage() {
    expect(find.text('HIGH RISK'), findsNothing,
        reason: "THE defect: A's client's risk stayed up");
    expect(find.text('4321'), findsNothing, reason: "A's client's score");
    expect(find.text('98765'), findsNothing);
    expect(find.text('06:45'), findsNothing, reason: "A's client's schedule");
    expect(find.text('Assign / Change Program'), findsNothing,
        reason: "A's paid plan opened B's services");
    expect(find.textContaining('HIGH RISK —'), findsNothing,
        reason: 'the AI summary of the assessment');
  }

  group('E1 / A-17 the client page', () {
    testWidgets('B pending, then refused: nothing of A; asked as B',
        (tester) async {
      await page(tester);
      final hold =
          server.holds['GET user_profiles:$memberB'] = Completer<void>();
      await become(tester, memberB);
      nothingOfThePage();
      await pumpUntil(tester, () => server.count('$_rpc:$memberB') == 1,
          what: 'the assessment read, in B\'s name');
      hold.complete();
      await pumpUntil(tester, () => seen(find.text('12 CIRCLE SCORE')),
          what: "B's (empty) page");
      await frames(tester);
      nothingOfThePage();
      expect(server.count('$_rpc:$memberA'), 0);
      await unmount(tester);
    });

    testWidgets('B\'s page answered, B\'s score / schedule / plan still out: '
        'nothing of A; then they fail: still nothing', (tester) async {
      await page(tester);
      const reads = ['user_scores', 'client_schedules', 'subscriptions'];
      for (final t in reads) {
        server.holds['GET $t:$memberB'] = Completer<void>();
      }
      server.seed('user_profiles', memberB, [
        {'id': _client, 'first_name': 'Alma', 'last_name': 'Stone'}
      ]);
      await become(tester, memberB);
      await pumpUntil(tester, () => seen(find.text('12 CIRCLE SCORE')),
          what: "B's page");
      await frames(tester);
      nothingOfThePage();
      for (final t in reads) {
        server.fails.add('GET $t:$memberB');
        server.holds['GET $t:$memberB']!.complete();
      }
      await pumpUntil(tester,
          () => seen(find.text("Couldn't check this client's plan.")),
          what: "B's failed plan check, said as B's");
      await frames(tester);
      nothingOfThePage();
      await unmount(tester);
    });

    testWidgets('signed out, then B: nothing of A', (tester) async {
      await page(tester);
      await become(tester, null);
      nothingOfThePage();
      await become(tester, memberB);
      nothingOfThePage();
      await unmount(tester);
    });

    testWidgets('control: a refreshed token re-reads nothing — no second '
        'logged assessment read', (tester) async {
      await page(tester);
      await tokenRefreshed(tester);
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.text('4321'), findsOneWidget);
      expect(server.calls.where((k) => k.endsWith(memberA)), isEmpty,
          reason: '${server.calls}');
      await unmount(tester);
    });

    testWidgets('control: the same coach\'s re-check of the plan does not '
        'flicker the services off', (tester) async {
      await page(tester);
      server.holds['GET subscriptions:$memberA'] = Completer<void>();
      c.invalidate(clientHasPaidPlanProvider(_client));
      await frames(tester, 2);
      expect(find.text('Assign / Change Program'), findsOneWidget);
      server.holds['GET subscriptions:$memberA']!.complete();
      await frames(tester);
      expect(find.text('Assign / Change Program'), findsOneWidget);
      await unmount(tester);
    });
  });

  testWidgets("A-23 A's attendees are not B's, pending or failed",
      (tester) async {
    server
      ..seed('event_registrations', memberA, [
        {'id': 'r1', 'user_id': 'u1', 'status': 'registered'}
      ])
      ..seed('event_attendee_profiles', memberA, [
        {
          'id': 'u1',
          'first_name': 'Ivy',
          'last_name': 'Lane',
          'email': 'ivy@guest.example'
        }
      ]);
    await host(tester,
        const EventAttendeesScreen(event: {'id': 'ev-1', 'title': 'Expo'}));
    await pumpUntil(tester, () => seen(find.textContaining('Ivy')), what: 'A');
    final hold =
        server.holds['GET event_registrations:$memberB'] = Completer<void>();
    await become(tester, memberB);
    expect(find.textContaining('Ivy'), findsNothing, reason: 'THE defect');
    expect(find.text('ivy@guest.example'), findsNothing);
    server.fails.add('GET event_registrations:$memberB');
    hold.complete();
    await pumpUntil(tester,
        () => seen(find.text('Could not load attendees.')), what: 'B failed');
    expect(find.textContaining('Ivy'), findsNothing);
    await unmount(tester);
  });

  // ── the sheets ────────────────────────────────────────────────────────────

  /// A page that stays mounted under the sheets, whoever signs in.
  Widget launcher() => Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Column(children: [
            const Text('THE PAGE'),
            TextButton(
                onPressed: () => showCoachNotesSheet(
                    context, ref, _client, 'Alma Stone'),
                child: const Text('notes')),
            TextButton(
                onPressed: () =>
                    showAssignActionItemSheet(context, ref, _client),
                child: const Text('action')),
            TextButton(
                onPressed: () => showCustomPriceDialogForTest(context, _client),
                child: const Text('price')),
          ]),
        ),
      );

  Finder field(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint);

  VoidCallback pressOf(WidgetTester tester, String label) {
    final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    return tester.widget<ButtonStyleButton>(button.first).onPressed!;
  }

  /// Opens [name] as A and puts A's work in it.
  Future<void> open(WidgetTester tester, String name) async {
    switch (name) {
      case 'program' || 'nutrition' || 'habits':
        await page(tester);
        final (button, ready) = switch (name) {
          'program' => ('Assign / Change Program', find.text('Plan of A')),
          'nutrition' => ('Set Nutrition Targets', find.text('1777')),
          _ => ('Assign Habits', find.text('7654')),
        };
        await tester.tap(find.text(button).last);
        await pumpUntil(tester, () => seen(ready), what: 'the sheet, as A');
        await frames(tester);
        if (name == 'program') {
          await tester.tap(find.text('Plan of A'));
          await frames(tester, 2);
        }
      case 'notes':
        await host(tester, launcher());
        await tester.tap(find.text('notes'));
        await pumpUntil(tester, () => seen(find.text('private about Alma')),
            what: "A's notes");
        await frames(tester);
        await tester.enterText(field('Add a private note…'), 'draft of A');
        await frames(tester, 2);
      case 'action':
        await host(tester, launcher());
        await tester.tap(find.text('action'));
        await frames(tester);
        await tester.enterText(
            field('Title (e.g. Hit 140g protein today)'), 'draft of A');
        await frames(tester, 2);
      case 'price':
        await host(tester, launcher());
        await tester.tap(find.text('price'));
        await frames(tester);
        await tester.enterText(find.byType(TextField), '4242');
        await frames(tester, 2);
    }
    server.calls.clear();
    server.writes.clear();
  }

  // sheet → (what A put in it, save button, where a save goes, origin)
  final sheets = {
    'program': (
      'Plan of A',
      'Assign Program',
      'workout_program_assignments',
      'AssignProgramSheet._assign',
    ),
    'nutrition': (
      '1777',
      'Save Nutrition Plan',
      'assign_nutrition_plan',
      'AssignNutritionSheet._save',
    ),
    'habits': (
      '7654',
      'Assign 1 Habit',
      'client_habits',
      'AssignHabitsSheet._save',
    ),
    'notes': (
      'draft of A',
      '',
      'coach_notes',
      'CoachNoteService.addNote',
    ),
    'action': (
      'draft of A',
      'Assign Action Item',
      'action_items',
      'AssignActionItemSheet._save',
    ),
    'price': (
      '4242',
      'Save',
      'coach_client_relationships',
      'ClientDetail.customPrice',
    ),
  };

  VoidCallback saveOf(WidgetTester tester, String name) {
    if (name == 'notes') {
      final tap = find.ancestor(
          of: find.byIcon(Icons.send), matching: find.byType(GestureDetector));
      return tester.widget<GestureDetector>(tap.first).onTap!;
    }
    return pressOf(tester, sheets[name]!.$2);
  }

  List<CoachWrite> theWrites() => [
        for (final w in server.writes)
          if (!w.path.contains('/storage/')) w
      ];

  for (final e in sheets.entries) {
    final name = e.key;
    final (draft, _, table, origin) = e.value;

    Finder drafted() => find.text(draft);

    group('W14/W19 $name', () {
      for (final next in [memberB, null]) {
        final who = next == null ? 'signs out' : 'becomes B';
        testWidgets('A $who: the draft is gone and the sheet closes, unsaid',
            (tester) async {
          await open(tester, name);
          expect(drafted(), findsOneWidget, reason: 'premise');
          await become(tester, next);
          expect(drafted(), findsNothing,
              reason: "THE defect: A's work stayed on screen");
          await frames(tester, 10);
          if (name == 'notes' || name == 'action' || name == 'price') {
            expect(find.text('THE PAGE').hitTestable(), findsOneWidget,
                reason: 'the sheet closed and only the sheet');
          }
          expect(find.byType(SnackBar), findsNothing);
          expect(theWrites(), isEmpty);
          await unmount(tester);
        });
      }

      testWidgets('B signs in and the save fires before any frame: nothing is '
          'sent, and it is recorded', (tester) async {
        await open(tester, name);
        final save = saveOf(tester, name);
        await tester.runAsync(() => signInAs(memberB));
        save();
        await frames(tester);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester);
        expect(theWrites(), isEmpty,
            reason: "THE defect: A's work was saved by B");
        expect(reported.map((f) => f.origin), contains(origin));
        expect(reported.firstWhere((f) => f.origin == origin).error.toString(),
            contains('the signed-in account changed'));
        expect(find.byType(SnackBar), findsNothing,
            reason: "B is told nothing about A's save");
        await unmount(tester);
      });

      testWidgets("A's save in flight when B signs in: nothing is said to B, "
          'the page underneath stays', (tester) async {
        await open(tester, name);
        final keys = [
          for (final m in ['POST', 'PATCH'])
            for (final t in [table, 'rpc/$table']) '$m $t:$memberA'
        ];
        final hold = Completer<void>();
        for (final k in keys) {
          server.holds[k] = hold;
        }
        saveOf(tester, name)();
        await pumpUntil(tester, () => theWrites().isNotEmpty,
            what: "A's save sent");
        expect(theWrites().first.who, memberA);
        await tester.runAsync(() => signInAs(memberB));
        hold.complete(); // lands before B's first frame
        await frames(tester, 12);
        expect(find.byType(SnackBar), findsNothing);
        expect(drafted(), findsNothing);
        expect(find.byType(MaterialApp), findsOneWidget);
        if (name == 'notes' || name == 'action' || name == 'price') {
          expect(find.text('THE PAGE').hitTestable(), findsOneWidget,
              reason: 'the page was popped with the sheet');
        } else {
          expect(find.byType(ClientDetailScreen), findsOneWidget);
        }
        await unmount(tester);
      });

      testWidgets('control: a refreshed token keeps the draft, and the save is '
          "the coach's own", (tester) async {
        await open(tester, name);
        await tokenRefreshed(tester);
        expect(drafted(), findsOneWidget,
            reason: 'a refreshed token is the same coach');
        saveOf(tester, name)();
        await pumpUntil(
            tester,
            () => theWrites().any((w) => w.path.endsWith('/$table')),
            what: 'the save');
        await frames(tester, 10);
        expect(theWrites().map((w) => w.who).toSet(), {memberA});
        final row = theWrites().lastWhere((w) => w.path.endsWith('/$table'));
        if (name == 'notes' || name == 'action' || name == 'program') {
          expect(row.body['coach_id'], memberA);
        }
        if (name == 'habits') {
          expect((row.body['rows'] as List).single['coach_id'], memberA);
        }
        await unmount(tester);
      });
    });
  }

  testWidgets("A's note is not deleted by B, and B is told nothing",
      (tester) async {
    await open(tester, 'notes');
    final del = tester.widget<GestureDetector>(find
        .ancestor(
            of: find.byIcon(Icons.close), matching: find.byType(GestureDetector))
        .first);
    await tester.runAsync(() => signInAs(memberB));
    del.onTap!();
    await frames(tester);
    expect(theWrites(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await unmount(tester);
  });

  testWidgets("a date picker A left open over the action sheet goes with it",
      (tester) async {
    await open(tester, 'action');
    await tester.tap(find.text('Due date (optional)'));
    await frames(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget, reason: 'premise');
    await become(tester, memberB);
    await frames(tester, 10);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('THE PAGE').hitTestable(), findsOneWidget);
    await unmount(tester);
  });

  testWidgets("A's late prefill does not land in front of B", (tester) async {
    await page(tester);
    final hold =
        server.holds['GET client_nutrition_plans:$memberA'] = Completer<void>();
    await tester.tap(find.text('Set Nutrition Targets').last);
    await frames(tester);
    await pumpUntil(tester,
        () => server.count('GET client_nutrition_plans:$memberA') == 1,
        what: "A's prefill sent");
    await tester.runAsync(() => signInAs(memberB));
    hold.complete();
    await frames(tester, 10);
    expect(find.text('1777'), findsNothing);
    expect(find.text('secret of A'), findsNothing);
    await unmount(tester);
  });
}
