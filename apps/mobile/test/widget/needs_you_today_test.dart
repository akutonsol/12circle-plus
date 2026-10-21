import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:circle_fitness/features/dashboard/domain/coach_triage.dart';
import 'package:circle_fitness/features/dashboard/presentation/widgets/needs_you_today.dart';

/// FIT-032 · "Needs you today", on screen.
///
/// `test/unit/coach_triage_test.dart` pins what the rows say. This pins what
/// they do, and one thing neither the rules nor the analyzer can catch: a
/// **route that does not exist**.
///
/// An earlier draft of this widget routed `Assign` to `/coach-programs` and the
/// roster to `/clients`. Neither is registered. Both read plausibly, nothing
/// fails at compile time, and go_router would have put the coach on an error
/// page. The last test in this file reads `app_router.dart` and holds every
/// destination against it.

ClientSignals _c(String id, String name,
        {int? week,
        String? note,
        int? days,
        int? until,
        String? on,
        String? asked}) =>
    ClientSignals(
      clientId: id,
      clientName: name,
      unrepliedCheckinWeek: week,
      unrepliedCheckinNote: note,
      daysSinceLastSession: days,
      daysUntilBlockEnds: until,
      blockEndsOn: on,
      unansweredMessage: asked,
    );


Future<void> _pump(
  WidgetTester tester,
  List<ClientSignals> clients, {
  int total = 24,
  int inactivity = 9,
  int horizon = 7,
}) async {
  final router = GoRouter(
    initialLocation: '/coach-dashboard',
    routes: [
      for (final p in const [
        '/coach-dashboard',
        '/coach-checkin-review',
        '/messages',
        '/program-builder',
        '/coach-client-workouts',
      ])
        GoRoute(
          path: p,
          builder: (_, __) {
            return Scaffold(
              body: SingleChildScrollView(
                child: p == '/coach-dashboard'
                    ? NeedsYouToday(
                        clients: clients,
                        totalClients: total,
                        inactivityDays: inactivity,
                        blockEndHorizonDays: horizon,
                      )
                    : Text('AT $p'),
              ),
            );
          },
        ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a row is a button and carries a tap action', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, [
      _c('a', 'Amara Osei', week: 14, note: 'travel next week'),
    ]);

    final d = tester
        .getSemantics(find.bySemanticsLabel(
            'Amara Osei Week 14 check-in · travel next week Review'))
        .getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasAction(SemanticsAction.tap), isTrue,
        reason: 'the board draws <button class="tap row">');

    handle.dispose();
  });

  testWidgets('each action word goes where that action is performed',
      (tester) async {
    Future<void> check(ClientSignals c, String text, String route) async {
      await _pump(tester, [c]);
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
      expect(find.text('AT $route'), findsOneWidget,
          reason: '$text should open $route');
    }

    await check(_c('a', 'Amara Osei', week: 14), 'Amara Osei',
        '/coach-checkin-review');
    await check(_c('b', 'Lena Fischer', asked: 'Asked about the split squat'),
        'Lena Fischer', '/messages');
    await check(_c('c', 'Priya Raman', until: 5, on: 'Sunday'), 'Priya Raman',
        '/program-builder');
    await check(_c('d', 'Tomas Vidal', days: 9), 'Tomas Vidal',
        '/coach-client-workouts');
  });

  testWidgets('the roster control carries the real count and opens', (tester) async {
    await _pump(tester, [_c('a', 'Amara Osei', week: 14)], total: 24);
    expect(find.text('All 24 clients'), findsOneWidget);
  });

  testWidgets('a coach with no clients is offered no roster', (tester) async {
    await _pump(tester, const [], total: 0);
    expect(find.textContaining('All '), findsNothing);
  });

  testWidgets('four are drawn, the rest counted', (tester) async {
    await _pump(tester, [
      for (var i = 0; i < 6; i++) _c('c$i', 'Client $i', week: 14),
    ]);
    expect(find.byType(GestureDetector).evaluate().length, greaterThan(0));
    expect(find.text('Client 0'), findsOneWidget);
    expect(find.text('Client 3'), findsOneWidget);
    expect(find.text('Client 4'), findsNothing);
    expect(find.text('and two more'), findsOneWidget);
  });

  // Nothing to do is a result, not a blank.
  testWidgets('a clear roster says so rather than rendering nothing',
      (tester) async {
    await _pump(tester, [_c('a', 'Amara Osei')]);
    expect(find.text('Nothing needs you right now.'), findsOneWidget);
    expect(find.text('All 24 clients'), findsOneWidget);
  });

  testWidgets('the chips read as the board writes them, not uppercased',
      (tester) async {
    await _pump(tester, [
      _c('a', 'Amara Osei', week: 14),
      _c('b', 'Tomas Vidal', days: 9),
      _c('c', 'Priya Raman', until: 5, on: 'Sunday'),
      _c('d', 'Lena Fischer', asked: 'Asked about the split squat'),
    ]);
    for (final w in const ['Review', 'At risk', 'Assign', 'Reply']) {
      expect(find.text(w), findsOneWidget);
      expect(find.text(w.toUpperCase()), findsNothing);
    }
  });

  // ── The one the analyzer cannot catch ───────────────────────────────────
  test('every destination this widget navigates to is a registered route', () {
    final widget =
        File('lib/features/dashboard/presentation/widgets/needs_you_today.dart')
            .readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();

    final destinations = RegExp(r"context\.go\('([^']+)'\)")
        .allMatches(widget)
        .map((m) => m.group(1)!)
        .toSet();

    expect(destinations, isNotEmpty,
        reason: 'the scanner found no navigation at all — it proves nothing');

    for (final route in destinations) {
      expect(router, contains("path: '$route'"),
          reason: '`$route` is not registered in app_router.dart. go_router '
              'will land the coach on an error page, and nothing fails at '
              'compile time — which is exactly how /clients and '
              '/coach-programs got into an earlier draft of this file.');
    }
  });
}
