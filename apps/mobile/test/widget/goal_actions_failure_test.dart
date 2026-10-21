// QAX-COR-08 (+ Workstream B's goal_service.updateProgress row) — goal actions
// must not fail invisibly.
//
// Before the fix "Mark achieved" and "Delete" awaited the service inside
// PopupMenuButton.onSelected with no handler (the app has no global error
// handler, so a failure was an unhandled async error the member never saw), and
// "Update progress" ignored the `false` that updateProgress returns on failure.
import 'package:circle_fitness/features/goals/data/goal_service.dart';
import 'package:circle_fitness/features/goals/data/models/goal.dart';
import 'package:circle_fitness/features/goals/domain/goal_provider.dart';
import 'package:circle_fitness/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _goal = Goal(
  id: 'g1', clientId: 'c1', coachId: null, title: 'Run 5k', type: 'custom',
  startValue: 0, currentValue: 1, targetValue: 5, unit: 'km',
  targetDate: null, status: 'active', completedAt: null,
  createdAt: DateTime(2026, 9, 1),
);

class _FakeGoals implements GoalService {
  _FakeGoals({this.fail = false});
  final bool fail;
  final calls = <String>[];

  @override
  Future<List<Goal>> getMyGoals() async => [_goal];
  @override
  Future<void> complete(String id) async {
    calls.add('complete');
    if (fail) throw Exception('simulated failure');
  }
  @override
  Future<void> deleteGoal(String id) async {
    calls.add('delete');
    if (fail) throw Exception('simulated failure');
  }
  @override
  Future<bool> updateProgress(String id, double currentValue) async {
    calls.add('update');
    return !fail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(GoalService svc) => ProviderScope(
      overrides: [goalServiceProvider.overrideWithValue(svc)],
      child: const MaterialApp(home: GoalsScreen()),
    );

Future<void> _choose(WidgetTester tester, String item) async {
  await tester.tap(find.byIcon(Icons.more_horiz));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('QAX-COR-08 a failed goal action is surfaced', () {
    for (final item in ['Mark achieved', 'Delete']) {
      testWidgets('"$item" failure shows a message, no unhandled error', (tester) async {
        final svc = _FakeGoals(fail: true);
        await tester.pumpWidget(_screen(svc));
        await tester.pumpAndSettle();
        await _choose(tester, item);

        expect(tester.takeException(), isNull);
        expect(svc.calls, hasLength(1));
        expect(find.text(goalActionFailedMessage), findsOneWidget);
      });
    }

    testWidgets('"Update progress" failure (service returns false) is shown', (tester) async {
      final svc = _FakeGoals(fail: true);
      await tester.pumpWidget(_screen(svc));
      await tester.pumpAndSettle();
      await _choose(tester, 'Update progress');
      await tester.enterText(find.byType(TextField), '2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(svc.calls, ['update']);
      expect(find.text(goalActionFailedMessage), findsOneWidget);
    });
  });

  group('QAX-COR-08 positive controls', () {
    for (final item in ['Mark achieved', 'Delete']) {
      testWidgets('"$item" success shows no failure message', (tester) async {
        final svc = _FakeGoals();
        await tester.pumpWidget(_screen(svc));
        await tester.pumpAndSettle();
        await _choose(tester, item);

        expect(tester.takeException(), isNull);
        expect(svc.calls, hasLength(1));
        expect(find.text(goalActionFailedMessage), findsNothing);
      });
    }
  });
}
