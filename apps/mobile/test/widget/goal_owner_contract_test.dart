import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/goals/data/goal_service.dart';
import 'package:circle_fitness/features/goals/domain/goal_provider.dart';
import 'package:circle_fitness/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c round 2 · what is new in the goals service and provider: the changes
// take the account they are made for, and a list is kept per account. Apart from
// goal_actions_are_their_owners_test because fd5d076 has neither: this file
// cannot compile there, and that one must fail there for its stated reasons.

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
  Finder text(String s) => find.text(s);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: GoalsScreen())));
    await settle(tester);
  }

  testWidgets('a failed refresh of a genuinely empty list keeps it, and says so',
      (tester) async {
    server.rows['goals']!.removeAt(0);
    await show(tester);
    server.fails.add('GET goals:$memberA');
    c.invalidate(goalsOfProvider(memberA));
    await settle(tester);
    expect(text('No goals yet'), findsOneWidget);
    expect(text("Couldn't load your latest goals"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
  test("a list is read, and kept, only as its member", () async {
    final hold = server.holds['GET goals:$memberA'] = Completer<void>();
    final provider = goalsOfProvider(memberA);
    c.listen(provider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await signInAs(memberB);
    hold.complete();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(c.read(provider), isA<AsyncError<Object?>>(), reason: 'landed as B');
    expect(reported.single.origin, 'goalsOfProvider');
    // Asked for with B signed in: B's are not read into A's list.
    final asked = server.log.length;
    c.invalidate(provider);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(server.log.length, asked);
    expect(c.read(provider).hasValue, isFalse);
    // Control: A again.
    await signInAs(memberA);
    c.invalidate(provider);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(c.read(provider).requireValue.single.title, 'Bench 100 kg');
  });

  test('a change for a member no longer signed in is not sent, and is recorded '
      'where it was swallowed', () async {
    await signInAs(memberB);
    final svc = GoalService();
    for (final change in [
      () => svc.updateProgressFor(memberA, 'g-b', 1),
      () => svc.completeFor(memberA, 'g-b'),
      () => svc.deleteGoalFor(memberA, 'g-b'),
    ]) {
      await expectLater(change(), throwsStateError);
    }
    expect(writes(), isEmpty);
    expect(reported.map((f) => f.origin), ['GoalService.updateProgress']);
  });

  test('control: the same changes, for the member signed in', () async {
    final svc = GoalService();
    expect(await svc.updateProgressFor(memberA, 'g-a', 95), isTrue);
    await svc.completeFor(memberA, 'g-a');
    await svc.deleteGoalFor(memberA, 'g-a');
    expect(writes(), hasLength(3));
    expect(reported, isEmpty);
  });
}
