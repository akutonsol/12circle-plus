import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/classes/presentation/whats_on_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

// P0-FL-59f round 4 (SEC6) · What's on, B's read failed, B taps the screen's own
// Try again: A's "Booked" and "Joined" rows came up as B's until B's read
// landed. The view is mounted as it is, over the real reads and real sign-ins.
//
// HOW TO SEE IT FAIL: git checkout 956c12e -- apps/mobile/lib

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    setFailureSink((_) {});
    final day = DateTime.now().toUtc();
    for (final who in [memberA, memberB]) {
      server
        ..seed('classes', who, [
          {
            'id': 'k-1',
            'title': 'Spin',
            'type': 'hiit',
            'is_online': true,
            'capacity': 10,
            'scheduled_at': day.add(const Duration(days: 1)).toIso8601String(),
          }
        ])
        ..seed('challenges', who, [
          {
            'id': 'ch-1',
            'title': 'Steps',
            'type': 'steps',
            'status': 'active',
            'is_active': true,
            'start_date': day
                .subtract(const Duration(days: 1))
                .toIso8601String()
                .split('T')[0],
            'end_date':
                day.add(const Duration(days: 9)).toIso8601String().split('T')[0],
          }
        ]);
    }
    server
      ..seed('class_bookings', memberA, [
        {'class_id': 'k-1', 'user_id': memberA, 'status': 'confirmed'}
      ])
      ..seed('challenge_participants', memberA, [
        {'challenge_id': 'ch-1', 'user_id': memberA, 'progress': 1}
      ]);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  bool seen(Finder f) => f.evaluate().isNotEmpty;
  Finder booked() => find.textContaining('Booked');
  Finder joined() => find.textContaining('Joined');
  Finder tryAgain() => find.text('Try again');

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(currentUserProvider, (_, __) {});
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: WhatsOnView()))));
    await pumpUntil(tester, () => seen(booked()) && seen(joined()),
        what: "A's list");
    await frames(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  for (final (source, theirs) in [
    ('classes', booked),
    ('challenges', joined),
  ]) {
    testWidgets("SEC6 B's $source failed, B taps Try again: the failure stays "
        "and none of A's rows come up; then B's own", (tester) async {
      await show(tester);
      server.fails.add('GET $source:$memberB');
      await tester.runAsync(() => signInAs(memberB));
      await pumpUntil(tester, () => seen(tryAgain()), what: "B's failure");
      expect(theirs(), findsNothing);
      server.fails.clear();
      final hold = server.holds['GET $source:$memberB'] = Completer<void>();
      final before = server.count('GET $source:$memberB');
      await tester.tap(tryAgain());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(theirs(), findsNothing,
            reason: "THE defect: A's $source were B's after one tap");
      }
      await pumpUntil(
          tester, () => server.count('GET $source:$memberB') > before,
          what: 'the retry is asked');
      expect(theirs(), findsNothing);
      expect(tryAgain(), findsOneWidget, reason: "B's failure stays meanwhile");
      hold.complete();
      await pumpUntil(tester, () => !seen(tryAgain()), what: "B's own");
      expect(theirs(), findsNothing);
      expect(find.textContaining('Spin'), findsOneWidget);
      await unmount(tester);
    });
  }

  testWidgets("A's Try again, tapped after B signed in and before any frame: "
      "neither A's rows nor A's failure are B's", (tester) async {
    await show(tester);
    server.fails.add('GET challenges:$memberA');
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await pumpUntil(tester, () => seen(tryAgain()), what: "A's failure");
    final tap = tester
        .widget<GestureDetector>(find
            .ancestor(of: tryAgain(), matching: find.byType(GestureDetector))
            .first)
        .onTap!;
    server
      ..holds['GET classes:$memberB'] = Completer<void>()
      ..holds['GET challenges:$memberB'] = Completer<void>();
    await tester.runAsync(() => signInAs(memberB));
    tap();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(booked(), findsNothing, reason: 'frame $i');
      expect(joined(), findsNothing, reason: 'frame $i');
      expect(tryAgain(), findsNothing, reason: "A's failure, frame $i");
    }
    await unmount(tester);
  });

  testWidgets("control: the member's own failed refresh keeps 'Booked', and "
      'Try again brings the rest back', (tester) async {
    await show(tester);
    server.fails.add('GET challenges:$memberA');
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await pumpUntil(tester, () => seen(tryAgain()), what: 'the failure');
    expect(booked(), findsOneWidget);
    server.fails.clear();
    await tester.tap(tryAgain());
    await pumpUntil(tester, () => !seen(tryAgain()), what: 'read again');
    expect(booked(), findsOneWidget);
    expect(joined(), findsOneWidget);
    await unmount(tester);
  });
}
