import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/presentation/dynamic_program_builder_screen.dart';

/// The coach "Generate week 1" step, driven through the real screen with a fake
/// service. The fake reproduces the engine's three real outcomes (verified on the
/// local replay): a complete week, ENGINE_NO_SELECTION, and ENGINE_WEEK_EXISTS.
class _Pg implements Exception {
  _Pg(this.message, [this.code = 'P0001']);
  final String message;
  final String code;
}

class _FakeSvc extends Fake implements CoachProgramService {
  _FakeSvc(this.outcomes);
  final List<Object> outcomes; // each: a result Map, or an exception to throw
  final calls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> planProgram(Map<String, dynamic> strategy) async => {
        'mesocycles': [
          {'name': 'Accumulation', 'weeks': [1, 4], 'volume_target': 1.0, 'intensity_target': 7}
        ],
        'weeks': [
          {'week': 1, 'phase': 'Accumulation', 'volume_multiplier': 1.0, 'intensity': 7,
           'split': ['Push', 'Pull', 'Legs']}
        ],
      };

  @override
  Future<String?> createEngineProgram(Map<String, dynamic> strategy, Map<String, dynamic> plan,
          {String? name}) async =>
      'prog-1';

  @override
  Future<Map<String, dynamic>?> materializeWeek(
      String programId, int week, Map<String, dynamic> context) async {
    calls.add(context);
    final o = outcomes.removeAt(0);
    if (o is Exception) throw o;
    return o as Map<String, dynamic>;
  }
}

const _complete = {
  'week': 1, 'sessions_created': 3,
  'sessions': [
    {'session': 'Push', 'exercises': 5},
    {'session': 'Pull', 'exercises': 5},
    {'session': 'Legs', 'exercises': 5},
  ],
};

Future<_FakeSvc> _pump(WidgetTester t, List<Object> outcomes, {bool flag = true}) async {
  final svc = _FakeSvc(outcomes);
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      currentUserProfileProvider.overrideWith((ref) async => {'role': 'coach'}),
      coachProgramServiceProvider.overrideWithValue(svc),
    ],
    child: MaterialApp(home: DynamicProgramBuilderScreen(engineWeekGeneration: flag)),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Plan program'));
  await t.pumpAndSettle();
  await t.tap(find.text('Create program (v1)'));
  await t.pumpAndSettle();
  return svc;
}

void main() {
  testWidgets('flag OFF: no Generate step, and the coach is told the program has no days', (t) async {
    final svc = await _pump(t, [], flag: false);
    expect(find.byKey(const ValueKey('generate-week-1')), findsNothing);
    expect(find.textContaining('no training days yet'), findsOneWidget);
    expect(svc.calls, isEmpty, reason: 'the engine must not be called with the flag off');
  });

  testWidgets('generation uses the type the program was SAVED with, not a later chip change', (t) async {
    final svc = await _pump(t, [_complete]); // saved as the default 'Hypertrophy'
    await t.tap(find.text('Fat Loss'));        // coach changes the chip afterwards
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(svc.calls.single['goal'], 'hypertrophy',
        reason: 'week 1 must match the saved program, not the current selection');
  });

  testWidgets('a complete week is reported with its real totals', (t) async {
    final svc = await _pump(t, [_complete]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(find.textContaining('Week 1 is ready — 3 training days, 15 exercises'), findsOneWidget);
    expect(svc.calls.single.containsKey('replace_existing'), isFalse,
        reason: 'a first generation must never ask to replace');
  });

  testWidgets('no intelligence data: an actionable message, nothing claimed', (t) async {
    await _pump(t, [_Pg('ENGINE_NO_SELECTION: the coaching engine selected no exercises for week 1 …')]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(find.textContaining("Couldn't pick exercises yet"), findsOneWidget);
    expect(find.textContaining('none have been cleared for Program Builder'), findsOneWidget);
    expect(find.textContaining('Nothing was saved'), findsOneWidget);
    expect(find.textContaining('is ready'), findsNothing);
  });

  testWidgets('a pre-186 "success" with no exercise counts is NOT shown as success', (t) async {
    await _pump(t, [{'week': 1, 'sessions_created': 3, 'sessions': [{'session': 'Push', 'trace_id': 'x'}]}]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(find.textContaining('is ready'), findsNothing);
    expect(find.textContaining("isn't available on this server yet"), findsOneWidget);
  });

  testWidgets('week already exists → Keep: nothing replaced, no second call', (t) async {
    final svc = await _pump(t, [_Pg('ENGINE_WEEK_EXISTS: week 1 … already has 3 training day(s).')]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(find.text('Replace week 1?'), findsOneWidget);
    expect(find.textContaining('including any changes you made by hand'), findsOneWidget);
    await t.tap(find.text('Keep week 1'));
    await t.pumpAndSettle();
    expect(svc.calls, hasLength(1), reason: 'keeping must not call the engine again');
    expect(find.textContaining('nothing was changed'), findsOneWidget);
  });

  testWidgets('dismissing the Replace dialog (tap outside) is KEEP, never replace', (t) async {
    final svc = await _pump(t, [_Pg('ENGINE_WEEK_EXISTS: week 1 … already has 3 training day(s).')]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(find.text('Replace week 1?'), findsOneWidget);
    await t.tapAt(const Offset(5, 5)); // the modal barrier
    await t.pumpAndSettle();
    expect(find.text('Replace week 1?'), findsNothing);
    expect(svc.calls, hasLength(1), reason: 'an ambiguous dismissal must not delete a week');
  });

  testWidgets('week already exists → Replace: exactly one replacing call, then success', (t) async {
    final svc = await _pump(t, [
      _Pg('ENGINE_WEEK_EXISTS: week 1 … already has 3 training day(s).'),
      _complete,
    ]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Replace'));
    await t.pumpAndSettle();
    expect(svc.calls, hasLength(2));
    expect(svc.calls.first.containsKey('replace_existing'), isFalse);
    expect(svc.calls.last['replace_existing'], isTrue,
        reason: 'replacement is sent only after the coach confirmed it');
    expect(find.textContaining('Week 1 is ready'), findsOneWidget);
  });

  testWidgets('another coach\'s programme (42501) is refused in plain words', (t) async {
    await _pump(t, [_Pg('not authorized for this program', '42501')]);
    await t.tap(find.byKey(const ValueKey('generate-week-1')));
    await t.pumpAndSettle();
    expect(find.textContaining("can't generate workouts for this programme"), findsOneWidget);
  });
}
