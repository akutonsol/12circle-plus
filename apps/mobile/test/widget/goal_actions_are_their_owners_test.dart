import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/goals/data/goal_service.dart';
import 'package:circle_fitness/features/goals/domain/goal_provider.dart';
import 'package:circle_fitness/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/pump_until.dart';
import '../support/settled.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c round 2 · /goals: the card, dialog, sheet and date picker are the
// member's they were built for, whatever frame has run since; a list (a genuine
// empty one too) is only ever its own member's; a first load that failed can be
// tried again.
//
// HOW TO SEE IT FAIL: `git checkout fd5d076 --` lib/features/goals.

const _support =
    'try again in a moment. If it keeps happening, contact support.';

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

  List<Asked> writes() => server.writes('goals');
  int reads(String uid) => server.log
      .where((a) => a.method == 'GET' && a.table == 'goals' && a.who == uid)
      .length;
  Finder text(String s) => find.text(s);
  String? signedIn() => Supabase.instance.client.auth.currentUser?.id;
  Iterable<AppFailure> accountChanged() => reported
      .where((f) => '${f.error}'.contains('the signed-in account changed'));

  Future<void> settle(WidgetTester tester) => settledFrames(tester, server,
      step: const Duration(milliseconds: 50));

  /// Real time passes and answers land; no frame runs.
  Future<void> noFrame(WidgetTester tester) => settledNoFrame(tester, server);

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: GoalsScreen())));
    await settle(tester);
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'the account to change');
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  Future<void> frames(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await frames(tester);
    await tester.tap(text(item));
    await frames(tester);
  }

  /// The rendered menu's own handler, as it was built.
  PopupMenuItemSelected<String> menuOf(WidgetTester tester) => tester
      .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>).first)
      .onSelected!;

  Future<void> openNew(WidgetTester tester, String title) async {
    await tester.tap(text('New Goal'));
    await frames(tester);
    await tester.enterText(find.byType(TextField).first, title);
    await tester.pump();
  }

  group('no frame since the switch', () {
    for (final action in ['update', 'complete', 'delete']) {
      for (final to in [memberB, null]) {
        testWidgets(
            "A's \"$action\" chosen with ${to == null ? 'nobody' : 'B'} signed in: "
            'nothing is sent or opened, it is recorded', (tester) async {
          await show(tester);
          final menu = menuOf(tester);
          await tester.runAsync(() => to == null ? signOut() : signInAs(to));
          expect(signedIn(), to, reason: 'premise');
          menu(action);
          await noFrame(tester);
          expect(writes(), isEmpty);
          expect(accountChanged(), hasLength(1));
          await settle(tester);
          expect(find.byType(AlertDialog), findsNothing,
              reason: "A's value is not opened for B");
          expect(find.textContaining("Couldn't"), findsNothing);
          await done(tester);
        });
      }

      testWidgets(
          "A's \"$action\" chosen in the turn the client changes: nothing is sent",
          (tester) async {
        await show(tester);
        final menu = menuOf(tester);
        await tester.runAsync(() async {
          final switching = signInAs(memberB);
          expect(signedIn(), memberB, reason: 'premise: before any event');
          menu(action);
          await switching;
        });
        await settle(tester);
        expect(writes(), isEmpty,
            reason: "THE defect: a change of A's was sent as B");
        expect(accountChanged(), hasLength(1));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.textContaining("Couldn't"), findsNothing);
        await done(tester);
      });

      testWidgets('control: "$action" works for the same member, across a token '
          'refresh', (tester) async {
        await show(tester);
        final menu = menuOf(tester);
        final before = c.read(currentUserProvider);
        await tester.runAsync(refreshSession);
        await noFrame(tester);
        expect(identical(c.read(currentUserProvider), before), isFalse,
            reason: 'premise: the event arrived');
        menu(action);
        await settle(tester);
        if (action == 'update') {
          await tester.enterText(find.byType(TextField), '95');
          await tester.tap(text('Save'));
          await settle(tester);
        }
        expect(writes().map((w) => w.who), [memberA]);
        expect(reported, isEmpty);
        await done(tester);
      });
    }

    testWidgets("A's dialog, opened and then switched: never drawn for B",
        (tester) async {
      await show(tester);
      menuOf(tester)('update'); // pushed, not yet built
      await tester.runAsync(() => signInAs(memberB));
      await tester.pump(); // its first frame
      expect(text('Update progress'), findsNothing,
          reason: "THE defect: A's dialog was built for B, and stayed");
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(text('Row 2k'), findsOneWidget);
      await done(tester);
    });

    testWidgets("A's Save in the dialog: nothing is sent, the dialog goes",
        (tester) async {
      await show(tester);
      await choose(tester, 'Update progress');
      await tester.enterText(find.byType(TextField), '95');
      await tester.pump();
      final save = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed!;
      await tester.runAsync(() => signInAs(memberB));
      save();
      await noFrame(tester);
      expect(writes(), isEmpty);
      expect(accountChanged(), hasLength(1), reason: 'recorded, once');
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });
  });

  group('in flight across A->B', () {
    for (final (item, method) in [
      ('Mark achieved', 'PATCH'),
      ('Delete', 'DELETE'),
    ]) {
      testWidgets('"$item", failing, no frame since: B is told nothing',
          (tester) async {
        final hold = server.holds['$method goals:$memberA'] = Completer<void>();
        server.fails.add('$method goals:$memberA');
        await show(tester);
        await choose(tester, item);
        await settle(tester);
        expect(writes(), hasLength(1), reason: 'premise');
        await tester.runAsync(() => signInAs(memberB));
        hold.complete();
        await noFrame(tester);
        await settle(tester);
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(reported.map((f) => f.origin), contains(startsWith('GoalsScreen.')));
        expect(text('Row 2k'), findsOneWidget);
        expect(writes().map((w) => w.who), [memberA]);
        await done(tester);
      });
    }

    for (final fails in [false, true]) {
      testWidgets("a create${fails ? ', refused' : ''}: A's, and B is told nothing",
          (tester) async {
        final hold = server.holds['POST goals:$memberA'] = Completer<void>();
        if (fails) server.fails.add('POST goals:$memberA');
        await show(tester);
        await openNew(tester, 'Private aim');
        await tester.tap(text('Create Goal'));
        await settle(tester);
        expect(writes(), hasLength(1), reason: 'premise');
        await become(tester, memberB);
        expect(find.byType(BottomSheet), findsNothing);
        hold.complete();
        await settle(tester);
        expect(find.textContaining("Couldn't"), findsNothing,
            reason: "A's failure is not B's news");
        expect(find.textContaining('Private aim'), findsNothing);
        expect(text('Row 2k'), findsOneWidget);
        expect(writes().map((w) => w.who), [memberA]);
        expect(writes().single.body['client_id'], memberA);
        await done(tester);
      });
    }

    testWidgets('a create, refused, no frame since: B is told nothing',
        (tester) async {
      final hold = server.holds['POST goals:$memberA'] = Completer<void>();
      server.fails.add('POST goals:$memberA');
      await show(tester);
      await openNew(tester, 'Private aim');
      await tester.tap(text('Create Goal'));
      await settle(tester);
      await tester.runAsync(() => signInAs(memberB));
      hold.complete();
      await noFrame(tester);
      await settle(tester);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      await done(tester);
    });
  });

  testWidgets('a date picker open over the new-goal sheet goes on a switch',
      (tester) async {
    await show(tester);
    await openNew(tester, 'Private aim');
    await tester.tap(text('Target date (optional)'));
    await frames(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget, reason: 'premise');
    await become(tester, memberB);
    expect(find.byType(DatePickerDialog), findsNothing,
        reason: "THE defect: A's picker stayed in front of B");
    expect(find.byType(BottomSheet), findsNothing);
    expect(text('Row 2k'), findsOneWidget);
    await done(tester);
  });

  testWidgets('control: the date picker stays, and picks, across a token refresh',
      (tester) async {
    await show(tester);
    await openNew(tester, 'Deadlift 140');
    await tester.tap(text('Target date (optional)'));
    await frames(tester);
    final before = c.read(currentUserProvider);
    await tester.runAsync(refreshSession);
    await settle(tester);
    expect(identical(c.read(currentUserProvider), before), isFalse,
        reason: 'premise: the event arrived');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(text('OK'));
    await frames(tester);
    expect(text('Target date (optional)'), findsNothing, reason: 'it was picked');
    await tester.tap(text('Create Goal'));
    await settle(tester);
    expect(writes().single.body['target_date'], isNotNull);
    await done(tester);
  });

  group('whose list', () {
    for (final afterB in [false, true]) {
      testWidgets(
          "A's held first read landing ${afterB ? 'after' : 'before'} B's is dropped",
          (tester) async {
        final holdA = server.holds['GET goals:$memberA'] = Completer<void>();
        final holdB = server.holds['GET goals:$memberB'] = Completer<void>();
        await show(tester);
        await become(tester, memberB);
        if (afterB) {
          holdB.complete();
          await settle(tester);
          expect(text('Row 2k'), findsOneWidget);
        }
        holdA.complete();
        await settle(tester);
        expect(text('Bench 100 kg'), findsNothing);
        if (!afterB) holdB.complete();
        await settle(tester);
        expect(text('Row 2k'), findsOneWidget);
        expect(text('Bench 100 kg'), findsNothing);
        await done(tester);
      });
    }

    // Loading -> loading is not announced by riverpod, so a kept list is not
    // dropped by B's read starting: the list is dropped by whose it is.
    testWidgets("A's refresh in flight when B signs in, B's read pending: "
        "nothing of A's, and A's late answer changes nothing", (tester) async {
      await show(tester);
      expect(text('Bench 100 kg'), findsOneWidget, reason: 'premise');
      final holdA = server.holds['GET goals:$memberA'] = Completer<void>();
      final holdB = server.holds['GET goals:$memberB'] = Completer<void>();
      final asked = reads(memberA);
      unawaited(tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh());
      await settle(tester);
      expect(reads(memberA) - asked, 1, reason: 'premise: in flight');
      expect(text('Bench 100 kg'), findsOneWidget, reason: 'control: A keeps it');
      await become(tester, memberB);
      expect(text('Bench 100 kg'), findsNothing,
          reason: "THE defect: A's goals were shown to B");
      expect(reads(memberB), 1, reason: "premise: B's is pending");
      expect(text('No goals yet'), findsNothing);
      holdA.complete();
      await settle(tester);
      expect(text('Bench 100 kg'), findsNothing);
      expect(text('No goals yet'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      holdB.complete();
      await settle(tester);
      expect(text('Row 2k'), findsOneWidget);
      expect(text('Bench 100 kg'), findsNothing);
      await done(tester);
    });

    for (final empty in [false, true]) {
      testWidgets(
          'a ${empty ? 'genuinely empty ' : ''}list refreshed before the switch '
          "is flushed is not shown to B", (tester) async {
        if (empty) server.rows['goals']!.removeAt(0);
        await show(tester);
        expect(text(empty ? 'No goals yet' : 'Bench 100 kg'), findsOneWidget,
            reason: 'premise');
        final hold = server.holds['GET goals:$memberB'] = Completer<void>();
        final refresh = empty
            ? null
            : tester
                .widget<RefreshIndicator>(find.byType(RefreshIndicator))
                .onRefresh;
        await tester.runAsync(() async {
          await signInAs(memberB);
          if (refresh != null) {
            await refresh(); // A's control: no frame, nothing flushed
          } else {
            c.invalidate(myGoalsProvider);
          }
        });
        await settle(tester);
        expect(text('Bench 100 kg'), findsNothing,
            reason: 'watching the uid by select, riverpod takes this for a '
                "refresh: AsyncData(isLoading: true, value: A's)");
        expect(text('No goals yet'), findsNothing,
            reason: "A's empty list is not B's answer");
        hold.complete();
        await settle(tester);
        expect(text('Row 2k'), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets('control: genuinely none, on the first load', (tester) async {
      server.rows['goals']!.removeAt(0);
      await show(tester);
      expect(text('No goals yet'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
      await done(tester);
    });

    testWidgets('a token refresh reads nothing again', (tester) async {
      await show(tester);
      final before = c.read(currentUserProvider);
      final asked = reads(memberA);
      await tester.runAsync(refreshSession);
      await settle(tester);
      expect(identical(c.read(currentUserProvider), before), isFalse,
          reason: 'premise: the event arrived');
      expect(reads(memberA), asked,
          reason: 'THE defect: every token refresh read the goals again');
      expect(text('Bench 100 kg'), findsOneWidget);
      await done(tester);
    });

    testWidgets('a first load that failed says so and can be tried again',
        (tester) async {
      server.fails.add('GET goals:$memberA');
      await show(tester);
      expect(text("Couldn't load your goals"), findsOneWidget,
          reason: 'THE defect: a dead end');
      expect(text('No goals yet'), findsNothing);
      server.fails.clear();
      final hold = server.holds['GET goals:$memberA'] = Completer<void>();
      final asked = reads(memberA);
      await tester.tap(text('Try again'));
      await settle(tester);
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      expect(reads(memberA) - asked, 1);
      hold.complete();
      await settle(tester);
      expect(text('Bench 100 kg'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });

  });

  group('the service', () {
    test('updateProgress signed out is a recorded failure, not a quiet false',
        () async {
      await signOut();
      await expectLater(GoalService().updateProgress('g-a', 1), throwsStateError);
      expect(reported.single.origin, 'GoalService.updateProgress');
      expect(writes(), isEmpty);
    });

  });

  testWidgets('a delete that failed says delete', (tester) async {
    server.fails.add('DELETE goals:$memberA');
    await show(tester);
    await choose(tester, 'Delete');
    await settle(tester);
    expect(text("Couldn't delete your goal — $_support"), findsOneWidget);
    await done(tester);
  });
}
