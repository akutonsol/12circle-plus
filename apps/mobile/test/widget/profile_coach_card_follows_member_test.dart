import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_change_server.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-RM-1 (C14-62b-03) · Profile's "MY COACH" card draws the coach read for the
// member signed in now, and nobody else's. It read
// `assignedCoachProvider.valueOrNull`: while B's read was pending (or after it
// failed) B was shown A's coach — name, avatar and the Cancel Coach button
// bound to A's coach's id.
//
// The REAL MyCoachSection and the REAL provider; no AccountScope; the card
// STAYS mounted across a real A -> B switch on the auth client.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/coach/domain/coach_provider.dart
// lib/features/profile/presentation/profile_screen.dart`.

const _a = memberA;
const _b = memberB;
const _rel = 'coach_client_relationships';

void main() {
  final server = CoachChangeServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    server.coachOf[_a] = 'c-a';
    server.coachOf[_b] = 'c-b';
    server.profiles['c-a'] = {'id': 'c-a', 'first_name': 'Anna', 'last_name': 'Ames'};
    server.profiles['c-b'] = {'id': 'c-b', 'first_name': 'Bea', 'last_name': 'Burr'};
  });
  tearDown(resetFailureSink);

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> frames(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(_a));
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MyCoachSection(onCoachCancelled: () {}))),
      ),
    ));
    await pumpUntil(t, () => seen(find.text('Coach Anna Ames')), what: "A's coach");
  }

  Future<void> close(WidgetTester t) async {
    for (final g in server.gates.values) {
      if (!g.isCompleted) g.complete();
    }
    await frames(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    await t.runAsync(signOut);
  }

  void nothingOfA() {
    expect(find.text('Coach Anna Ames'), findsNothing,
        reason: "THE defect: B was shown A's coach");
    expect(find.text('Cancel Coach'), findsNothing,
        reason: "THE defect: B was offered to cancel A's coach");
  }

  testWidgets("B's read pending: nothing of A's coach, and no \"no coach\" "
      'either — still reading', (t) async {
    await open(t);
    server.gates['GET $_rel:$_b'] = Completer();
    await t.runAsync(() => signInAs(_b));
    await pumpUntil(t, () => server.named(_rel, who: _b).isNotEmpty, what: "B's read");
    await frames(t);
    nothingOfA();
    expect(find.text('No coach assigned yet'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    server.gates['GET $_rel:$_b']!.complete();
    await pumpUntil(t, () => seen(find.text('Coach Bea Burr')), what: "B's coach");
    await close(t);
  });

  testWidgets("B's read failed: the section is hidden (F-15), never A's coach, "
      'never "no coach"; recorded once', (t) async {
    await open(t);
    server.failing.add('GET $_rel:$_b');
    await t.runAsync(() => signInAs(_b));
    await pumpUntil(t, () => server.named(_rel, who: _b).isNotEmpty, what: "B's read");
    await frames(t, 12);
    nothingOfA();
    expect(find.text('No coach assigned yet'), findsNothing);
    expect(find.text('MY COACH'), findsNothing);
    expect(reported.where((f) => f.origin == 'assignedCoach'), hasLength(1));
    await close(t);
  });

  testWidgets('A signs out: nothing of A', (t) async {
    await open(t);
    await t.runAsync(signOut);
    await frames(t);
    nothingOfA();
    await close(t);
  });

  testWidgets('control: a token refresh keeps the card, without a spinner or a '
      're-read', (t) async {
    await open(t);
    await frames(t);
    final reads = server.named(_rel).length;
    await t.runAsync(refreshSession);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 30));
      expect(find.text('Coach Anna Ames'), findsOneWidget, reason: 'flicker');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    await frames(t);
    expect(server.named(_rel).length, reads, reason: 'a token refresh re-read it');
    expect(reported, isEmpty);
    await close(t);
  });

  testWidgets('control: same member out and back in: their coach again',
      (t) async {
    await open(t);
    await t.runAsync(signOut);
    await frames(t);
    await t.runAsync(() => signInAs(_a));
    await pumpUntil(t, () => seen(find.text('Coach Anna Ames')), what: 'again');
    expect(find.text('Cancel Coach'), findsOneWidget);
    await close(t);
  });
}
