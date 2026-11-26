import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/action_items/presentation/assign_action_item_sheet.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach_notes/presentation/coach_notes_sheet.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
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

  // ── the page ──────────────────────────────────────────────────────────────

  Future<void> page(WidgetTester tester) async {
    await host(tester,
        const ClientDetailScreen(
            clientId: _client, clientName: 'Alma Stone', owner: memberA));
    await pumpUntil(tester,
        () => seen(find.text('4321')) && seen(find.text('06:45')) &&
            seen(find.text('HIGH RISK')) &&
            seen(find.text('Assign / Change Program')),
        what: "A's client page");
    await frames(tester);
    server.calls.clear();
  }

  /// No read of the client went out as B (the realtime tick and B's own
  /// profile are not the client's).
  void nothingAskedAs(String uid) => expect(
      server.calls.where((k) => k.endsWith(uid)), isEmpty,
      reason: "THE defect: A's client was read by an account that never "
          'opened their page');

  void nothingOfThePage() {
    expect(find.text('Alma Stone'), findsNothing,
        reason: "THE defect: A's client's name stayed up");
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
    for (final next in [memberB, null]) {
      testWidgets(
          '${next == null ? 'signed out' : 'B'}: nothing of A, the name '
          'included, and nothing is asked', (tester) async {
        // B could read this client too: only who OPENED the page decides.
        server.data['user_profiles']![memberB] =
            server.data['user_profiles']![memberA]!;
        await page(tester);
        await become(tester, next);
        nothingOfThePage();
        await frames(tester, 10);
        nothingOfThePage();
        expect(find.byIcon(Icons.arrow_back_ios), findsOneWidget,
            reason: 'a way off the page');
        nothingAskedAs(next ?? 'anon');
        await unmount(tester);
      });
    }

    testWidgets("A's reads still out when B signs in land on nobody, and no "
        'further step goes out as B', (tester) async {
      await page(tester);
      final hold =
          server.holds['GET user_profiles:$memberA'] = Completer<void>();
      c.invalidate(clientDetailProvider(_client));
      await pumpUntil(tester,
          () => server.count('GET user_profiles:$memberA') == 1,
          what: "A's re-read");
      await become(tester, memberB);
      hold.complete();
      await frames(tester, 10);
      nothingOfThePage();
      expect(server.calls.where((k) => k.contains('get_client_assessment')),
          isEmpty);
      nothingAskedAs(memberB);
      await unmount(tester);
    });

    testWidgets('pushed by A, B signs in before its first frame: never drawn, '
        'nothing read', (tester) async {
      await host(tester, launcher());
      Navigator.of(tester.element(find.text('THE PAGE'))).push(
          MaterialPageRoute<void>(builder: (_) => const ClientDetailScreen(
              clientId: _client, clientName: 'Alma Stone', owner: memberA)));
      server.calls.clear();
      await tester.runAsync(() => signInAs(memberB));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        nothingOfThePage();
      }
      nothingAskedAs(memberB);
      await unmount(tester);
    });

    testWidgets("control: B's own page about the same client, over A's, reads "
        "as B and says B's failures", (tester) async {
      await page(tester);
      server.seed('user_profiles', memberB, [
        {'id': _client, 'first_name': 'Alma', 'last_name': 'Stone'}
      ]);
      server.fails.add('GET subscriptions:$memberB');
      await become(tester, memberB);
      Navigator.of(tester.element(find.byType(ClientDetailScreen))).push(
          MaterialPageRoute<void>(builder: (_) => const ClientDetailScreen(
              clientId: _client, clientName: 'Alma Stone', owner: memberB)));
      await pumpUntil(tester,
          () => seen(find.text("Couldn't check this client's plan.")),
          what: "B's page and its failed plan check");
      expect(server.count('$_rpc:$memberB'), 1);
      expect(server.count('$_rpc:$memberA'), 0);
      expect(find.text('HIGH RISK'), findsNothing);
      expect(find.text('4321'), findsNothing);
      await unmount(tester);
    });

    for (final frameFirst in [true, false]) {
      testWidgets("SEC5b B's own page about the client pushed as B signs in, "
          "A's page undrawn since${frameFirst ? ' but one frame' : ''}: B reads "
          'it, and is not left on a refusal', (tester) async {
        await page(tester);
        for (final table in ['user_profiles', 'subscriptions']) {
          server.seed(table, memberB, server.data[table]![memberA]!);
        }
        final bs = server.holds['GET user_profiles:$memberB'] =
            Completer<void>();
        await tester.runAsync(() => signInAs(memberB));
        if (frameFirst) await tester.pump();
        Navigator.of(tester.element(find.byType(ClientDetailScreen))).push(
            MaterialPageRoute<void>(builder: (_) => const ClientDetailScreen(
                clientId: _client, clientName: 'Alma Stone', owner: memberB)));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('HIGH RISK'), findsNothing);
          expect(find.text('4321'), findsNothing);
          expect(find.text('06:45'), findsNothing);
          expect(find.text('Could not load this client'), findsNothing,
              reason: "a refusal from before B's page is not B's failure");
        }
        bs.complete();
        await pumpUntil(tester,
            () => seen(find.text('Assign / Change Program')),
            what: "B's own page (THE defect: a refusal it could not retry)");
        await frames(tester);
        expect(find.text('Could not load this client'), findsNothing);
        expect(server.count('$_rpc:$memberB'), 1);
        expect(server.count('$_rpc:$memberA'), 0);
        expect(find.text('HIGH RISK'), findsNothing);
        await unmount(tester);
      });
    }

    testWidgets('control: the same coach signing back in has their page again',
        (tester) async {
      await page(tester);
      await become(tester, null);
      nothingOfThePage();
      await become(tester, memberA);
      await pumpUntil(tester, () => seen(find.text('HIGH RISK')),
          what: "A's page");
      expect(find.text('Alma Stone'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('control: a token event that fires keeps the name up',
        (tester) async {
      await page(tester);
      await tokenRefreshed(tester);
      expect(find.text('Alma Stone'), findsWidgets);
      await unmount(tester);
    });

    testWidgets("what is opened from A's page, tapped after B signed in and "
        'before any frame: nothing opens, nothing is asked', (tester) async {
      for (final label in [
        'Assign / Change Program',
        'Set Nutrition Targets',
        'Assign Habits',
        'Assign Action Item',
        'Send Video Response',
        'Private Notes',
        'Set Custom Price',
      ]) {
        await tester.runAsync(() => signInAs(memberA));
        await page(tester);
        reported.clear();
        final tap = tester
            .widget<GestureDetector>(find
                .ancestor(
                    of: find.text(label).last,
                    matching: find.byType(GestureDetector))
                .first)
            .onTap!;
        await tester.runAsync(() => signInAs(memberB));
        tap();
        await frames(tester);
        expect(find.byType(BottomSheet), findsNothing, reason: label);
        expect(find.byType(AlertDialog), findsNothing, reason: label);
        expect(find.byType(TextField), findsNothing, reason: label);
        nothingOfThePage();
        nothingAskedAs(memberB);
        expect(reported.map((f) => '${f.error}'),
            contains(contains('the signed-in account changed')),
            reason: label);
        await unmount(tester);
      }
    });
  });

  group('the Action Center', () {
    Finder button(String label) => find.widgetWithText(TextButton, label);

    Future<void> openEdit(WidgetTester tester) async {
      await page(tester);
      await tester.tap(button('Edit').first);
      await frames(tester);
      await tester.enterText(find.byType(TextField), 'EDITED BY A');
      await frames(tester, 2);
      expect(find.text('Edit Action'), findsOneWidget, reason: 'premise');
    }

    VoidCallback press(WidgetTester tester, Finder f) =>
        tester.widget<TextButton>(f).onPressed!;

    for (final next in [memberB, null]) {
      testWidgets(
          'A ${next == null ? 'signs out' : 'becomes B'}: the Edit dialog '
          'closes and its text is gone', (tester) async {
        await openEdit(tester);
        await become(tester, next);
        expect(find.text('EDITED BY A'), findsNothing,
            reason: "THE defect: A's dialog stayed up");
        await frames(tester, 10);
        expect(find.text('Edit Action'), findsNothing);
        expect(tester.takeException(), isNull);
        await become(tester, memberA);
        await pumpUntil(tester, () => seen(find.text('HIGH RISK')), what: 'A');
        expect(find.text('EDITED BY A'), findsNothing);
        await unmount(tester);
      });
    }

    testWidgets('Save fires after B signed in and before any frame: nothing '
        'changes, nothing throws', (tester) async {
      await openEdit(tester);
      final save = press(tester, button('Save'));
      await tester.runAsync(() => signInAs(memberB));
      save();
      await frames(tester, 10);
      expect(tester.takeException(), isNull);
      expect(find.text('EDITED BY A'), findsNothing);
      expect(reported.map((f) => f.origin), contains('CoachActionCenter'));
      await unmount(tester);
    });

    testWidgets('opened by A, B signs in before its first frame: never drawn',
        (tester) async {
      await page(tester);
      press(tester, button('Edit').first)();
      await tester.runAsync(() => signInAs(memberB));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Edit Action'), findsNothing);
      }
      await unmount(tester);
    });

    testWidgets('tapped after B signed in and before any frame: Edit, Approve '
        'and Dismiss do and say nothing', (tester) async {
      for (final label in ['Edit', 'Approve', 'Dismiss']) {
        await tester.runAsync(() => signInAs(memberA));
        await page(tester);
        final tap = press(tester, button(label).last);
        reported.clear();
        await tester.runAsync(() => signInAs(memberB));
        tap();
        await frames(tester);
        expect(find.byType(SnackBar), findsNothing, reason: label);
        expect(find.byType(AlertDialog), findsNothing, reason: label);
        expect(find.byType(BottomSheet), findsNothing, reason: label);
        expect(reported.map((f) => f.origin), contains('CoachActionCenter'));
        await unmount(tester);
      }
    });

    testWidgets("what A edited and cleared is not kept for B, nor what was "
        'said about it', (tester) async {
      await openEdit(tester);
      await tester.tap(button('Save'));
      await frames(tester);
      expect(find.text('EDITED BY A'), findsOneWidget, reason: 'premise');
      await tester.tap(button('Dismiss').first);
      await frames(tester, 2);
      expect(find.textContaining('Dismissed: EDITED BY A'), findsOneWidget,
          reason: 'premise');
      await become(tester, memberB);
      await frames(tester, 2);
      expect(find.textContaining('EDITED BY A'), findsNothing,
          reason: "THE defect: A's words stayed up for B");
      await become(tester, memberA);
      await pumpUntil(tester, () => seen(find.text('HIGH RISK')), what: 'A');
      expect(find.textContaining('EDITED BY A'), findsNothing);
      expect(button('Dismiss'), findsNWidgets(5),
          reason: 'a fresh page: nothing is cleared on it');
      await unmount(tester);
    });

    testWidgets('control: a refreshed token keeps the dialog, and it saves',
        (tester) async {
      await openEdit(tester);
      await tokenRefreshed(tester);
      expect(find.text('EDITED BY A'), findsOneWidget);
      await tester.tap(button('Save'));
      await frames(tester, 10);
      expect(find.text('Edit Action'), findsNothing);
      expect(find.text('EDITED BY A'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('what the Action Center said (R5)', () {
    Finder said() => find.textContaining('Dismissed: ');

    /// The page pushed over a first one, as a coach opens it, and one of its
    /// recommendations dismissed.
    Future<void> dismissed(WidgetTester tester) async {
      await host(tester, launcher());
      Navigator.of(tester.element(find.text('THE PAGE'))).push(
          MaterialPageRoute<void>(builder: (_) => const ClientDetailScreen(
              clientId: _client, clientName: 'Alma Stone', owner: memberA)));
      await pumpUntil(tester, () => seen(find.text('HIGH RISK')), what: 'A');
      await frames(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(said(), findsOneWidget, reason: 'premise');
    }

    for (final next in [memberB, null]) {
      final who = next == null ? 'A signs out' : 'B signs in';
      testWidgets('$who: it is not in the next frame', (tester) async {
        await dismissed(tester);
        await tester.runAsync(() => next == null ? signOut() : signInAs(next));
        await tester.pump();
        expect(said(), findsNothing,
            reason: "THE defect: A's client's recommendation was left up");
        await frames(tester);
        expect(find.byType(SnackBar), findsNothing);
        await unmount(tester);
      });

      testWidgets('A leaves the page and $who while it closes: not in the next '
          'frame', (tester) async {
        await dismissed(tester);
        Navigator.of(tester.element(find.byType(ClientDetailScreen))).pop();
        await tester.pump();
        await tester.runAsync(() => next == null ? signOut() : signInAs(next));
        await tester.pump();
        expect(said(), findsNothing);
        await unmount(tester);
      });
    }

    testWidgets('A leaves the page: it goes with it', (tester) async {
      await dismissed(tester);
      tester.state<NavigatorState>(find.byType(Navigator).first).popUntil(
          (r) => r.isFirst);
      await pumpUntil(tester, () => !seen(find.byType(ClientDetailScreen)),
          what: 'the page is gone', step: const Duration(milliseconds: 16));
      await tester.pump();
      expect(said(), findsNothing,
          reason: "THE defect: it outlived A's page");
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('control: a token event that fires keeps it up for its time',
        (tester) async {
      await dismissed(tester);
      final before = c.read(currentUserProvider);
      await tester.runAsync(refreshSession);
      await pumpUntil(tester, () => c.read(currentUserProvider) != before,
          what: 'the same coach as a new User');
      expect(said(), findsOneWidget);
      await frames(tester, 20);
      expect(said(), findsNothing, reason: 'its second is over');
      await unmount(tester);
    });

    // Round 5: the page takes down its own messages and nobody else's.
    for (final how in ['A leaves the page', 'B signs in', 'A signs out']) {
      testWidgets("$how: a message queued behind the page's is still said, and "
          "none of the page's is", (tester) async {
        await dismissed(tester);
        // A second of the page's, queued; then another screen's.
        await tester.tap(find.widgetWithText(TextButton, 'Dismiss').first);
        await tester.pump();
        ScaffoldMessenger.of(tester.element(find.byType(ClientDetailScreen)))
            .showSnackBar(const SnackBar(
                content: Text("Couldn't save — another screen's")));
        final other = find.textContaining("another screen's");
        expect(other, findsNothing, reason: 'premise: queued');
        if (how == 'A leaves the page') {
          tester.state<NavigatorState>(find.byType(Navigator).first).popUntil(
              (r) => r.isFirst);
          await pumpUntil(tester, () => !seen(find.byType(ClientDetailScreen)),
              what: 'the page is gone', step: const Duration(milliseconds: 16));
        } else {
          await tester.runAsync(
              () => how == 'B signs in' ? signInAs(memberB) : signOut());
        }
        await tester.pump();
        for (var i = 0; i < 20 && !seen(other); i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(said(), findsNothing, reason: "the page's own (frame $i)");
        }
        expect(other, findsOneWidget,
            reason: "THE defect: another screen's message was dropped with it");
        await frames(tester, 10);
        expect(other, findsOneWidget, reason: 'for its own time');
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets("A leaves the page while its message is queued behind another "
        "screen's: that one stays for its time, and the page's never comes up",
        (tester) async {
      await dismissed(tester);
      await frames(tester, 20);
      expect(said(), findsNothing, reason: 'premise: its second is over');
      final messenger =
          ScaffoldMessenger.of(tester.element(find.byType(ClientDetailScreen)));
      messenger.showSnackBar(const SnackBar(
          content: Text("another screen's"), duration: Duration(seconds: 2)));
      await frames(tester, 4);
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss').first);
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator).first).popUntil(
          (r) => r.isFirst);
      await frames(tester, 6);
      expect(find.byType(ClientDetailScreen), findsNothing);
      expect(find.text("another screen's"), findsOneWidget,
          reason: "THE defect: the page took down another screen's message");
      await pumpUntil(tester, () => !seen(find.text("another screen's")),
          what: 'its time is over', step: const Duration(milliseconds: 100));
      await frames(tester, 3);
      expect(find.byType(SnackBar), findsNothing,
          reason: "the page's queued message came up after it had gone");
      await unmount(tester);
    });

    testWidgets("A's 'Program assigned!' is not in the next frame for B",
        (tester) async {
      await page(tester);
      await tester.tap(find.text('Assign / Change Program').last);
      await pumpUntil(tester, () => seen(find.text('Plan of A')), what: 'A');
      await frames(tester);
      await tester.tap(find.text('Plan of A'));
      await frames(tester, 2);
      await tester.tap(find.text('Assign Program'));
      await pumpUntil(tester, () => seen(find.text('Program assigned!')),
          what: 'said to A');
      await tester.runAsync(() => signInAs(memberB));
      await tester.pump();
      expect(find.text('Program assigned!'), findsNothing);
      await unmount(tester);
    });

    testWidgets("control: a message of another page's is not taken down with a "
        'page that said nothing', (tester) async {
      await dismissed(tester);
      await frames(tester, 20);
      ScaffoldMessenger.of(tester.element(find.byType(ClientDetailScreen)))
          .showSnackBar(const SnackBar(content: Text('Program assigned!')));
      await frames(tester, 4);
      Navigator.of(tester.element(find.byType(ClientDetailScreen))).pop();
      await frames(tester, 8);
      expect(find.byType(ClientDetailScreen), findsNothing);
      expect(find.text('Program assigned!'), findsOneWidget);
      await unmount(tester);
    });
  });

  // The families that outlive their sheet and are invalidated before the next
  // coach's first read of them: Riverpod re-reads them as a REFRESH, which
  // holds the previous coach's rows as data.
  group('opened by B after A had it open', () {
    Future<void> aReadTheNotes(WidgetTester tester) async {
      await host(tester, launcher());
      await tester.tap(find.text('notes'));
      await pumpUntil(tester, () => seen(find.text('private about Alma')),
          what: "A's notes");
      Navigator.of(tester.element(find.text('private about Alma'))).pop();
      await frames(tester);
    }

    for (final (fate, drawn) in [
      ('still out', true),
      ('still out', false),
      ('failed', true),
      ('failed', false),
    ]) {
      testWidgets("the notes sheet, B's read $fate"
          "${drawn ? '' : ' and no frame since the switch'}: none of A's notes",
          (tester) async {
        await aReadTheNotes(tester);
        if (drawn) {
          await become(tester, memberB);
        } else {
          await tester.runAsync(() => signInAs(memberB));
        }
        if (fate == 'failed') {
          server.fails.add('GET coach_notes:$memberB');
        } else {
          server.holds['GET coach_notes:$memberB'] = Completer<void>();
        }
        await tester.tap(find.text('notes'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('private about Alma'), findsNothing,
              reason: "THE defect: A's private note was shown to B");
        }
        await pumpUntil(tester,
            () => server.count('GET coach_notes:$memberB') == 1,
            what: "B's own read");
        await frames(tester);
        expect(find.text('private about Alma'), findsNothing);
        if (fate == 'failed') {
          expect(find.text('Could not load notes'), findsOneWidget);
        } else {
          server.holds['GET coach_notes:$memberB']!.complete();
          await pumpUntil(tester,
              () => !seen(find.byType(CircularProgressIndicator)),
              what: "B's own (empty) notes");
          expect(find.text('Could not load notes'), findsNothing);
        }
        await unmount(tester);
      });
    }

    testWidgets("the notes sheet, A's re-read still out from before: none of "
        "A's notes", (tester) async {
      await aReadTheNotes(tester);
      server.holds['GET coach_notes:$memberA'] = Completer<void>();
      await tester.tap(find.text('notes'));
      await pumpUntil(tester,
          () => server.count('GET coach_notes:$memberA') > 1,
          what: "A's re-read");
      server.holds['GET coach_notes:$memberB'] = Completer<void>();
      await become(tester, memberB);
      await frames(tester, 10);
      await tester.tap(find.text('notes'));
      await frames(tester);
      expect(find.text('Private Notes · Alma Stone'), findsOneWidget,
          reason: "premise: B's own sheet");
      expect(find.text('private about Alma'), findsNothing);
      server.holds['GET coach_notes:$memberA']!.complete();
      await frames(tester);
      expect(find.text('private about Alma'), findsNothing);
      server.holds['GET coach_notes:$memberB']!.complete();
      await frames(tester);
      await unmount(tester);
    });

    testWidgets('control: the same coach opening them again sees them while '
        'they are re-read', (tester) async {
      await aReadTheNotes(tester);
      final hold = server.holds['GET coach_notes:$memberA'] = Completer<void>();
      await tester.tap(find.text('notes'));
      await frames(tester);
      expect(find.text('private about Alma'), findsOneWidget);
      hold.complete();
      await frames(tester);
      expect(find.text('private about Alma'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets("the Assign sheet, its list invalidated: none of A's programs",
        (tester) async {
      await page(tester);
      await tester.tap(find.text('Assign / Change Program').last);
      await pumpUntil(tester, () => seen(find.text('Plan of A')), what: 'A');
      Navigator.of(tester.element(find.text('Plan of A'))).pop();
      await frames(tester);
      for (final table in ['user_profiles', 'subscriptions']) {
        server.seed(table, memberB, server.data[table]![memberA]!);
      }
      await tester.runAsync(() => signInAs(memberB));
      c.invalidate(myProgramsProvider); // a program write does
      Navigator.of(tester.element(find.byType(ClientDetailScreen))).push(
          MaterialPageRoute<void>(builder: (_) => const ClientDetailScreen(
              clientId: _client, clientName: 'Alma Stone', owner: memberB)));
      await pumpUntil(tester,
          () => seen(find.text('Assign / Change Program')), what: "B's page");
      await frames(tester);
      final hold =
          server.holds['GET workout_programs:$memberB'] = Completer<void>();
      await tester.tap(find.text('Assign / Change Program').last);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Plan of A'), findsNothing,
            reason: "THE defect: A's programs were B's to assign");
      }
      hold.complete();
      await pumpUntil(tester,
          () => seen(find.textContaining('No programs yet')),
          what: "B's own");
      await unmount(tester);
    });
  });

  group('the client photo, full screen', () {
    Finder viewer() => find.byType(InteractiveViewer);
    Finder thumb() => find
        .ancestor(of: find.byType(Image), matching: find.byType(GestureDetector))
        .first;

    Future<VoidCallback> ready(WidgetTester tester) async {
      server
        ..photos.add('$_client/front.jpg')
        ..photos.add('p-1.jpg')
        ..seed('progress_photo_logs', memberA, [
          {'user_id': _client, 'storage_path': '$_client/p-1.jpg',
            'logged_at': '2026-11-01T00:00:00Z'}
        ]);
      await page(tester);
      await tester.tap(find.text('Progress'));
      await frames(tester, 10);
      expect(find.byType(Image), findsWidgets, reason: 'premise: a photo');
      return tester.widget<GestureDetector>(thumb()).onTap!;
    }

    Future<void> open(WidgetTester tester) async {
      (await ready(tester))();
      await frames(tester);
      expect(viewer(), findsOneWidget, reason: 'premise');
    }

    for (final next in [memberB, null]) {
      final who = next == null ? 'signs out' : 'becomes B';
      testWidgets('A $who: the photo closes', (tester) async {
        await open(tester);
        await become(tester, next);
        expect(viewer(), findsNothing,
            reason: "THE defect: A's client's photo stayed up");
        await frames(tester, 10);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(ModalBarrier).evaluate().length, 1,
            reason: 'the dialog route is gone, not only its content');
        await unmount(tester);
      });

      testWidgets('A taps it and $who before its first frame: never drawn',
          (tester) async {
        final tap = await ready(tester);
        tap();
        await tester
            .runAsync(() => next == null ? signOut() : signInAs(next));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(viewer(), findsNothing);
        }
        await unmount(tester);
      });
    }

    testWidgets('tapped after B signed in and before any frame: not opened',
        (tester) async {
      final tap = await ready(tester);
      await tester.runAsync(() => signInAs(memberB));
      tap();
      await frames(tester);
      expect(viewer(), findsNothing);
      expect(reported.map((f) => f.origin), contains('ClientDetail.showPhoto'));
      await unmount(tester);
    });

    testWidgets('control: a refreshed token keeps it, and a tap closes it',
        (tester) async {
      await open(tester);
      await tokenRefreshed(tester);
      expect(viewer(), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await frames(tester, 10);
      expect(viewer(), findsNothing);
      await unmount(tester);
    });
  });

  // The two page controls of round 1.
  group('E1 / A-17 the client page, same coach', () {

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

  // ── the sheets ────────────────────────────────────────────────────────────

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
          expect(
              name == 'notes'
                  ? find.byIcon(Icons.send)
                  : find.widgetWithText(
                      name == 'price' ? AlertDialog : BottomSheet,
                      sheets[name]!.$2),
              findsNothing,
              reason: "THE defect: A's sheet stayed open");
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
        // As the row policies do for a row stamped with another coach.
        server.fails.add('POST $table:$memberB');
        await tester.runAsync(() => signInAs(memberB));
        hold.complete(); // lands before B's first frame
        await frames(tester, 12);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 4);
        final asA = [for (final w in theWrites()) if (w.who == memberA) w];
        final asB = [for (final w in theWrites()) if (w.who == memberB) w];
        expect(asA, isNotEmpty);
        if (name == 'program' || name == 'habits') {
          // W20, the KNOWN gap (coach_program_service, SEC-R3): the insert that
          // follows the switch-off goes out as B, stamped A, and RLS refuses
          // it. Nothing else may.
          for (final w in asB) {
            expect((w.method, w.path.split('/').last), ('POST', table));
            final row = name == 'habits'
                ? (w.body['rows'] as List).single as Map
                : w.body;
            expect(row['coach_id'], memberA);
          }
          expect(asB.length, lessThanOrEqualTo(1));
        } else if (name == 'nutrition') {
          // The same KNOWN gap in the same file: the plan itself is one RPC, as
          // A, and the client's notice that follows it goes out as B. It names
          // neither coach. Nothing else may.
          for (final w in asB) {
            expect((w.path.split('/').last, w.body['type']),
                ('notifications', 'nutrition_assigned'));
          }
          expect(asB.length, lessThanOrEqualTo(1));
        } else {
          expect(asB, isEmpty, reason: 'every write is A\'s: $asB');
        }
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

      testWidgets("A's save fails after B signed in: nothing is said to B, "
          'and it is recorded', (tester) async {
        await open(tester, name);
        final hold = Completer<void>();
        for (final m in ['POST', 'PATCH']) {
          for (final t in [table, 'rpc/$table']) {
            server.holds['$m $t:$memberA'] = hold;
            server.fails.add('$m $t:$memberA');
          }
        }
        saveOf(tester, name)();
        await pumpUntil(tester, () => theWrites().isNotEmpty,
            what: "A's save sent");
        await tester.runAsync(() => signInAs(memberB));
        hold.complete();
        await frames(tester, 12);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 4);
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: A's failure was said to B");
        expect(find.textContaining("Couldn't save"), findsNothing);
        expect(drafted(), findsNothing);
        expect(theWrites().where((w) => w.who == memberB), isEmpty);
        expect(reported, isNotEmpty, reason: "A's failure is recorded");
        await unmount(tester);
      });

      testWidgets('A opens it and B signs in before its first frame: never '
          'drawn', (tester) async {
        if (name == 'program' || name == 'nutrition' || name == 'habits') {
          await page(tester);
        } else {
          await host(tester, launcher());
        }
        final label = switch (name) {
          'program' => 'Assign / Change Program',
          'nutrition' => 'Set Nutrition Targets',
          'habits' => 'Assign Habits',
          _ => name,
        };
        await tester.tap(find.text(label).last);
        await tester.runAsync(() => signInAs(memberB));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(TextField), findsNothing,
              reason: 'THE defect: B was given the form A opened');
          expect(find.textContaining('Alma Stone'), findsNothing);
          expect(find.widgetWithText(BottomSheet, 'Assign Program'),
              findsNothing);
        }
        expect(theWrites(), isEmpty);
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

  testWidgets("A's late habits do not land in front of B", (tester) async {
    await page(tester);
    final hold =
        server.holds['GET client_habits:$memberA'] = Completer<void>();
    await tester.tap(find.text('Assign Habits').last);
    await frames(tester);
    await pumpUntil(tester, () => server.count('GET client_habits:$memberA') == 1,
        what: "A's prefill sent");
    await tester.runAsync(() => signInAs(memberB));
    hold.complete();
    await frames(tester, 10);
    expect(find.text('7654'), findsNothing);
    expect(find.textContaining('Assign 1 Habit'), findsNothing);
    expect(theWrites(), isEmpty);
    await unmount(tester);
  });

  // Round 6 (ux): a message of a sheet's or the price dialog's went blank on a
  // switch but stayed up, an empty bar for the next account for up to 4 s.
  group("what a sheet or the price dialog said to A, once A leaves", () {
    Future<String> said(WidgetTester tester, String name) async {
      await open(tester, name);
      saveOf(tester, name)();
      final text = name == 'price'
          ? r'Custom price set to $4242/mo.'
          : 'Program assigned!';
      await pumpUntil(tester, () => seen(find.text(text)), what: 'said to A');
      await frames(tester, 3);
      return text;
    }

    for (final name in ['program', 'price']) {
      for (final next in [memberB, null]) {
        final who = next == null ? 'A signs out' : 'B signs in';
        testWidgets('$name: $who, and its bar goes, not just its text',
            (tester) async {
          final text = await said(tester, name);
          await tester.runAsync(
              () => next == null ? signOut() : signInAs(next));
          await tester.pump();
          expect(find.text(text), findsNothing);
          await frames(tester, 6); // well inside its 4 s
          expect(find.byType(SnackBar), findsNothing,
              reason: 'THE defect: an empty bar was left up for B');
          await unmount(tester);
        });
      }

      testWidgets("$name, control: another screen's bar queued behind it comes "
          'up for B and stays for its time', (tester) async {
        final text = await said(tester, name);
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
            .showSnackBar(const SnackBar(
                content: Text("another screen's"),
                duration: Duration(seconds: 2)));
        await tester.runAsync(() => signInAs(memberB));
        await pumpUntil(tester, () => seen(find.text("another screen's")),
            what: 'the next bar', step: const Duration(milliseconds: 100));
        await frames(tester, 15);
        expect(find.text("another screen's"), findsOneWidget,
            reason: "another screen's bar was taken down with A's");
        expect(find.text(text), findsNothing);
        await unmount(tester);
      });

      testWidgets('$name, control: a refreshed token keeps it up, with its text',
          (tester) async {
        final text = await said(tester, name);
        await tokenRefreshed(tester);
        expect(find.text(text), findsOneWidget);
        await unmount(tester);
      });
    }
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
