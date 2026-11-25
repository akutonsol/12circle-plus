import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/community/presentation/pods/pods_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c round 2 (B2) · /pods followed the account through riverpod, which
// needs a frame. In a hidden tab A's join landing with B signed in welcomed B to
// the pod, told B a join had failed, and read A's pods with B's session; and a
// Join button drawn for A joined B once B's pods had been read.
//
// No frame runs between the switch and the answer, or the tap.
// HOW TO SEE IT FAIL: `git checkout fd5d076 --` pods_screen.dart.

const _pods = 'accountability_pods';
const _members = 'accountability_pod_members';

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
  String? signedIn() => Supabase.instance.client.auth.currentUser?.id;
  Iterable<AppFailure> accountChanged() => reported
      .where((f) => '${f.error}'.contains('the signed-in account changed'));

  /// A's pods asked for with B's session.
  Iterable<Asked> crossReads() => server.log.where((a) =>
      a.who != memberA &&
      a.query.values.any((v) => v.contains(memberA)));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Real time passes and answers land; no frame runs.
  Future<void> noFrame(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.idle();
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

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  /// The rendered Join of [name]'s card, as it was built.
  VoidCallback joinOf(WidgetTester tester, String name) {
    final card =
        find.ancestor(of: text(name), matching: find.byType(Column)).first;
    return tester
        .widget<ElevatedButton>(find
            .descendant(
                of: find
                    .ancestor(of: card, matching: find.byType(Container))
                    .first,
                matching: find.byType(ElevatedButton))
            .first)
        .onPressed!;
  }

  void expectBsOwn(WidgetTester tester) {
    expect(find.textContaining('Joined pod!'), findsNothing,
        reason: "THE defect: B was welcomed to A's pod");
    expect(find.textContaining("Couldn't"), findsNothing,
        reason: "THE defect: B was told A's join failed");
    expect(find.textContaining('already in that pod'), findsNothing);
    expect(text('Bravo Pod'), findsNWidgets(2), reason: "B's own pod");
    expect(text('Alpha Pod'), findsOneWidget);
    expect(text('Charlie Pod'), findsOneWidget);
    expect(crossReads(), isEmpty,
        reason: "THE defect: A's pods were read with B's session");
  }

  for (final (name, arrange) in <(String, void Function())>[
    ('taken', () {}),
    ('refused', () => server.fails.add('POST $_members:$memberA')),
    ('a duplicate (23505)',
        () => server.rows[_members]!.add({'pod_id': 'p-c', 'user_id': memberA})),
  ]) {
    testWidgets("A's join, $name, landing with B signed in and no frame since",
        (tester) async {
      final hold = server.holds['POST $_members:$memberA'] = Completer<void>();
      await show(tester);
      arrange();
      joinOf(tester, 'Charlie Pod')();
      await settle(tester);
      expect(server.writes(_members), hasLength(1), reason: 'premise');
      await tester.runAsync(() => signInAs(memberB));
      expect(signedIn(), memberB, reason: 'premise');
      hold.complete();
      await noFrame(tester);
      await settle(tester);
      expectBsOwn(tester);
      expect(accountChanged(), hasLength(1), reason: 'recorded');
      expect(server.writes(_members).map((w) => w.who), [memberA]);
      await done(tester);
    });
  }

  testWidgets("A's join, landing with nobody signed in and no frame since",
      (tester) async {
    final hold = server.holds['POST $_members:$memberA'] = Completer<void>();
    await show(tester);
    joinOf(tester, 'Charlie Pod')();
    await settle(tester);
    await tester.runAsync(signOut);
    hold.complete();
    await noFrame(tester);
    await settle(tester);
    expect(find.textContaining('Joined pod!'), findsNothing);
    expect(text('Alpha Pod'), findsNothing);
    expect(crossReads(), isEmpty);
    await done(tester);
  });

  for (final fails in [false, true]) {
    testWidgets(
        "the read after A's join${fails ? ', failing,' : ''} landing with B "
        'signed in and no frame since', (tester) async {
      await show(tester);
      final hold = server.holds['GET $_pods:$memberA'] = Completer<void>();
      if (fails) server.fails.add('GET $_pods:$memberA');
      joinOf(tester, 'Charlie Pod')();
      await settle(tester);
      expect(find.textContaining('Joined pod!'), findsOneWidget, reason: 'premise');
      // The SnackBar comes in, stays, and goes.
      for (final s in [1, 5, 1, 1]) {
        await tester.pump(Duration(seconds: s));
      }
      expect(find.textContaining('Joined pod!'), findsNothing, reason: 'premise');
      await tester.runAsync(() => signInAs(memberB));
      hold.complete();
      await noFrame(tester);
      await settle(tester);
      expectBsOwn(tester);
      await done(tester);
    });
  }

  testWidgets("A's held first read landing after sign-out is dropped",
      (tester) async {
    final hold = server.holds['GET $_pods:$memberA'] = Completer<void>();
    await show(tester);
    await tester.runAsync(signOut);
    hold.complete();
    await noFrame(tester);
    await settle(tester);
    expect(text('My Pods'), findsNothing);
    expect(text('Alpha Pod'), findsNothing);
    expect(text('Charlie Pod'), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
    await tester.runAsync(() => signInAs(memberA));
    await settle(tester);
    expect(text('Alpha Pod'), findsNWidgets(2), reason: 'A, back again');
    await done(tester);
  });

  for (final bRead in [false, true]) {
    testWidgets(
        "A's Join pressed with B signed in and no frame since"
        "${bRead ? ", B's pods read" : ''}: nothing is sent", (tester) async {
      await show(tester);
      final join = joinOf(tester, 'Charlie Pod');
      if (!bRead) server.holds['GET $_pods:$memberB'] = Completer<void>();
      await tester.runAsync(() => signInAs(memberB));
      await noFrame(tester);
      // Any read flushes the provider fd5d076 followed the account through: the
      // screen's owner is B, and what A's button checks is B against B.
      if (bRead) {
        expect(c.read(currentUserProvider)?.id, memberB);
        await noFrame(tester);
        expect(server.asked('GET $_pods:$memberB'), isTrue, reason: 'premise');
      }
      join();
      await noFrame(tester);
      expect(server.writes(_members), isEmpty,
          reason: 'THE defect: a button of A joined B');
      expect(accountChanged(), hasLength(1), reason: 'recorded');
      server.holds['GET $_pods:$memberB']?.complete();
      await settle(tester);
      expectBsOwn(tester);
      // B's own button is B's.
      joinOf(tester, 'Charlie Pod')();
      await settle(tester);
      expect(server.writes(_members).single.body,
          {'pod_id': 'p-c', 'user_id': memberB});
      await done(tester);
    });
  }

  testWidgets("A's Join pressed in the turn the client changes: nothing is sent",
      (tester) async {
    await show(tester);
    final join = joinOf(tester, 'Charlie Pod');
    await tester.runAsync(() async {
      final switching = signInAs(memberB);
      expect(signedIn(), memberB, reason: 'premise: before any event');
      join();
      await switching;
    });
    await settle(tester);
    expect(server.writes(_members), isEmpty);
    expectBsOwn(tester);
    await done(tester);
  });

  testWidgets('control: the same member, across a token refresh with no frame',
      (tester) async {
    await show(tester);
    final token = Supabase.instance.client.auth.currentSession!.accessToken;
    final hold = server.holds['POST $_members:$memberA'] = Completer<void>();
    joinOf(tester, 'Charlie Pod')();
    await settle(tester);
    var refreshed = false;
    final sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.tokenRefreshed) refreshed = true;
    });
    await tester.runAsync(refreshSession);
    await noFrame(tester);
    expect(refreshed, isTrue, reason: 'premise: the event arrived');
    expect(Supabase.instance.client.auth.currentSession!.accessToken,
        isNot(token));
    hold.complete();
    await noFrame(tester);
    await settle(tester);
    expect(find.textContaining('Joined pod!'), findsOneWidget);
    expect(text('Charlie Pod'), findsNWidgets(2));
    expect(reported, isEmpty);
    unawaited(sub.cancel());
    await done(tester);
  });

  testWidgets('already a member, and the pods cannot be read: both are said',
      (tester) async {
    await show(tester);
    server.rows[_members]!.add({'pod_id': 'p-c', 'user_id': memberA});
    server.fails.add('GET $_pods:$memberA');
    joinOf(tester, 'Charlie Pod')();
    await settle(tester);
    expect(text("Couldn't load the latest pods"), findsOneWidget);
    expect(text("You're already in that pod."), findsOneWidget,
        reason: 'THE defect: nothing said what became of the join');
    expect(find.textContaining('Joined pod!'), findsNothing);
    await done(tester);
  });
}
