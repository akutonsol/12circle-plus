import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/community/presentation/pods/pods_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c (b) + E16 · /pods. A failed load was "No open pods yet", a failed
// join was nothing at all, two joins could be in flight, and member A's pods
// stayed for member B.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` pods_screen.dart.

const _pods = 'accountability_pods';
const _members = 'accountability_pod_members';
const _support =
    'try again in a moment. If it keeps happening, contact support.';

Map<String, Object?> _pod(String id, String name) => {
      'id': id, 'name': name, 'status': 'open', 'member_count': 2,
      'max_members': 8, 'description': 'Daily', 'meeting_frequency': 'Daily',
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
    server.rows[_pods] = [
      _pod('p-a', 'Alpha Pod'),
      _pod('p-b', 'Bravo Pod'),
      _pod('p-c', 'Charlie Pod'),
    ];
    server.rows[_members] = [
      {'pod_id': 'p-a', 'user_id': memberA},
      {'pod_id': 'p-b', 'user_id': memberB},
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

  Finder text(String s) => find.text(s);
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: PodsScreen())));
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

  /// Taps Join on [name]'s card.
  Future<void> join(WidgetTester tester, String name) async {
    final card = find.ancestor(of: text(name), matching: find.byType(Column)).first;
    final button = find.descendant(
        of: find.ancestor(of: card, matching: find.byType(Container)).first,
        matching: find.byType(ElevatedButton));
    await tester.tap(button.first, warnIfMissed: false);
    await settle(tester);
  }

  /// A's: in Alpha (listed under both headings), may join Bravo and Charlie.
  void expectAsPods() {
    expect(text('My Pods'), findsOneWidget);
    expect(text('Alpha Pod'), findsNWidgets(2));
    expect(text('Bravo Pod'), findsOneWidget);
    expect(text('Join'), findsNWidgets(2));
  }

  testWidgets('control: the pods load', (tester) async {
    await show(tester);
    expectAsPods();
    expect(reported, isEmpty);
    await done(tester);
  });

  testWidgets('control: genuinely no pods is said as none', (tester) async {
    server.rows[_pods] = [];
    await show(tester);
    expect(text('No open pods yet'), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    await done(tester);
  });

  for (final (name, arrange, hint) in <(String, void Function(), String)>[
    ('refused', () => server.fails.add('GET $_pods:$memberA'),
        'Try again in a moment. If it keeps happening, contact support.'),
    ('offline', () => server.offline.add('GET $_pods:$memberA'),
        'Check your connection and try again.'),
  ]) {
    testWidgets('a load that was $name is said, recorded, and retried once',
        (tester) async {
      arrange();
      await show(tester);
      // postgrest retries a GET that never reached the server (1 s, 2 s, 4 s).
      await pumpUntil(tester, () => text("Couldn't load your pods").evaluate().isNotEmpty,
          what: 'the failure', step: const Duration(milliseconds: 100));
      expect(text('No open pods yet'), findsNothing,
          reason: 'THE defect: a failed load was "no pods"');
      expect(text("Couldn't load your pods"), findsOneWidget);
      expect(text(hint), findsOneWidget);
      expect(reported.map((f) => f.origin), contains('PodsScreen.load'));
      expect(find.textContaining('SECRET_TABLE'), findsNothing);

      server.fails.clear();
      server.offline.clear();
      final hold = server.holds['GET $_pods:$memberA'] = Completer<void>();
      final before = server.log.length;
      await tester.tap(text('Try again'));
      await settle(tester);
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      expect(server.log.length - before, 2, reason: 'one load: two reads');
      hold.complete();
      await settle(tester);
      expectAsPods();
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });
  }

  for (final (name, arrange, hint) in <(String, void Function(), String)>[
    ('refused', () => server.fails.add('POST $_members:$memberA'), _support),
    ('offline', () => server.offline.add('POST $_members:$memberA'),
        'check your connection and try again.'),
  ]) {
    testWidgets('a join that was $name is said and recorded', (tester) async {
      arrange();
      await show(tester);
      await join(tester, 'Charlie Pod');
      expect(server.writes(_members), hasLength(1));
      expect(text("Couldn't join that pod — $hint"), findsOneWidget,
          reason: 'THE defect: nothing was said');
      expect(reported.map((f) => f.origin), contains('PodsScreen.joinPod'));
      expect(find.textContaining('Joined pod!'), findsNothing);
      expect(text('Join'), findsNWidgets(2), reason: 'and can be tried again');
      await done(tester);
    });
  }

  testWidgets('control: a join is said, and shows as joined', (tester) async {
    await show(tester);
    await join(tester, 'Charlie Pod');
    expect(server.writes(_members).single.body,
        {'pod_id': 'p-c', 'user_id': memberA});
    expect(find.textContaining('Joined pod!'), findsOneWidget);
    expect(text('Charlie Pod'), findsNWidgets(2));
    expect(text('Join'), findsOneWidget);
    expect(reported, isEmpty);
    await done(tester);
  });

  testWidgets('joined, then the read fails: joined stays, the failure is said',
      (tester) async {
    await show(tester);
    server.fails.add('GET $_pods:$memberA');
    await join(tester, 'Charlie Pod');
    expect(text('Charlie Pod'), findsNWidgets(2));
    expect(text("Couldn't load the latest pods"), findsOneWidget);
    expect(text('Join'), findsOneWidget, reason: 'joined is not offered again');
    await done(tester);
  });

  testWidgets('already a member (23505): the pods are read, nothing is invented',
      (tester) async {
    await show(tester);
    // Joined on another device since.
    server.rows[_members]!.add({'pod_id': 'p-c', 'user_id': memberA});
    await join(tester, 'Charlie Pod');
    expect(text('Charlie Pod'), findsNWidgets(2));
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(find.textContaining('Joined pod!'), findsNothing);
    await done(tester);
  });

  testWidgets('one join at a time', (tester) async {
    final hold = server.holds['POST $_members:$memberA'] = Completer<void>();
    await show(tester);
    await join(tester, 'Charlie Pod');
    expect(find.bySemanticsLabel('Joining'), findsOneWidget);
    await join(tester, 'Bravo Pod');
    await join(tester, 'Charlie Pod');
    expect(server.writes(_members).map((w) => w.body['pod_id']), ['p-c'],
        reason: 'THE defect: every tap sent another join');
    hold.complete();
    await settle(tester);
    expect(text('Join'), findsOneWidget);
    await done(tester);
  });

  group('A->B', () {
    testWidgets("B's read pending: nothing of A; then B's own", (tester) async {
      await show(tester);
      final hold = server.holds['GET $_pods:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(text('My Pods'), findsNothing,
          reason: "THE defect: A's pods stayed for B");
      expect(text('No open pods yet'), findsNothing);
      hold.complete();
      await settle(tester);
      expect(text('Bravo Pod'), findsNWidgets(2));
      expect(text('Alpha Pod'), findsOneWidget);
      await done(tester);
    });

    testWidgets("B's read failed: the failure, nothing of A", (tester) async {
      await show(tester);
      server.fails.add('GET $_pods:$memberB');
      await become(tester, memberB);
      expect(text('My Pods'), findsNothing);
      expect(text("Couldn't load your pods"), findsOneWidget);
      await done(tester);
    });

    for (final afterB in [false, true]) {
      testWidgets(
          "A's held read landing ${afterB ? 'after' : 'before'} B's is dropped",
          (tester) async {
        final holdA = server.holds['GET $_pods:$memberA'] = Completer<void>();
        final holdB = server.holds['GET $_pods:$memberB'] = Completer<void>();
        await show(tester);
        await become(tester, memberB);
        if (afterB) holdB.complete();
        await settle(tester);
        holdA.complete();
        await settle(tester);
        if (!afterB) {
          expect(text('My Pods'), findsNothing);
          holdB.complete();
          await settle(tester);
        }
        expect(text('Bravo Pod'), findsNWidgets(2));
        expect(text('Alpha Pod'), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets("A's join in flight: nothing of it is said or shown to B",
        (tester) async {
      final hold = server.holds['POST $_members:$memberA'] = Completer<void>();
      await show(tester);
      await join(tester, 'Charlie Pod');
      await become(tester, memberB);
      hold.complete();
      await settle(tester);
      expect(find.textContaining('Joined pod!'), findsNothing);
      expect(text('Charlie Pod'), findsOneWidget);
      expect(server.writes(_members).map((w) => w.who), [memberA]);
      await done(tester);
    });

    testWidgets("A's Join tapped with B already signed in sends nothing",
        (tester) async {
      await show(tester);
      final joinNow = tester
          .widgetList<ElevatedButton>(find.byType(ElevatedButton))
          .first
          .onPressed!;
      await tester.runAsync(() => signInAs(memberB)); // no frame
      joinNow();
      await settle(tester);
      expect(server.writes(_members), isEmpty,
          reason: 'THE defect: B was joined to the pod A tapped');
      await done(tester);
    });

    testWidgets('sign-out, then A again', (tester) async {
      await show(tester);
      await become(tester, null);
      expect(text('My Pods'), findsNothing);
      expect(text('Alpha Pod'), findsNothing);
      await become(tester, memberA);
      expectAsPods();
      await done(tester);
    });

    testWidgets('control: a token refresh keeps the pods, reads nothing again',
        (tester) async {
      await show(tester);
      final before = c.read(currentUserProvider);
      final asked = server.log.length;
      await tester.runAsync(refreshSession);
      await pumpUntil(
          tester, () => !identical(c.read(currentUserProvider), before),
          what: 'the refreshed session');
      await settle(tester);
      expectAsPods();
      expect(server.log.length, asked);
      await join(tester, 'Charlie Pod');
      expect(find.textContaining('Joined pod!'), findsOneWidget);
      await done(tester);
    });
  });
}
