import 'dart:async';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// P0-FL-6 (B): the coach dashboard's Requests tab label read
// `pendingRequestsProvider.valueOrNull?.isNotEmpty == true ? "Requests ●" :
// "Requests"`. A failed read had no value, so the label showed exactly what it
// shows for "no pending requests" — a failure shown as zero.
//
// HOW TO SEE IT FAIL: on 4d1d992 the failed-read test finds no
// "Requests — couldn't load" label and no error icon in the tab.

typedef _Rows = List<Map<String, dynamic>>;

Widget _dashboard(FutureOr<_Rows> Function() requests) => ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async => const []),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        coachNotificationsProvider
            .overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => requests()),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Finder _requestsTab() => find.ancestor(
    of: find.textContaining('Requests').first, matching: find.byType(Tab));

final _failedLabel = RegExp("Requests — couldn't load");

void main() {
  testWidgets('a failed requests read is not shown as no requests',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_dashboard(() => throw Exception('offline')));
    await _settle(tester);

    expect(find.text('Requests ●'), findsNothing);
    expect(find.bySemanticsLabel(_failedLabel), findsOneWidget,
        reason: 'THE defect: the label read exactly as "no pending requests"');
    expect(
        find.descendant(
            of: _requestsTab(), matching: find.byIcon(Icons.error_outline)),
        findsOneWidget,
        reason: 'a visible indicator, not only a screen-reader label');
    handle.dispose();
  });

  testWidgets('while loading, the label claims no count', (tester) async {
    final gate = Completer<_Rows>();
    await tester.pumpWidget(_dashboard(() => gate.future));
    await _settle(tester);

    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Requests ●'), findsNothing);
    expect(find.bySemanticsLabel(_failedLabel), findsNothing);
    gate.complete(const []);
    await _settle(tester);
  });

  testWidgets('control: pending requests show the dot', (tester) async {
    await tester.pumpWidget(_dashboard(() => const [
          {'id': 'r1'}
        ]));
    await _settle(tester);
    expect(find.text('Requests ●'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('control: no pending requests show the plain label',
      (tester) async {
    await tester.pumpWidget(_dashboard(() => const []));
    await _settle(tester);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Requests ●'), findsNothing);
    expect(find.bySemanticsLabel(_failedLabel), findsNothing);
  });
}
