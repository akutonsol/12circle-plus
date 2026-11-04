import 'package:circle_fitness/core/theme/twelve_circle_theme.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/resume_workout_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/in_memory_workout_session_store.dart';

// The Resume banner sits in a Row, and the app's theme gives every ElevatedButton
// `minimumSize: Size(double.infinity, 54)` — a full-width call to action. Inheriting
// that took the whole Row, so the text beside it wrapped one letter per line and
// the banner grew past the screen. Home does not scroll, so a client with an
// unfinished session lost the Today card and the banner's own Resume and close
// controls, with no way back.
//
// A release build draws that silently. Only the real theme reproduces it, so these
// tests pump `TwelveCircleTheme.theme` rather than a default MaterialApp.

const _widths = [320.0, 360.0, 375.0, 390.0, 430.0];
const _height = 812.0;
const _userId = 'client-1';

final _workout = Workout(
  id: 'workout-1',
  title: 'Lower Body A',
  description: '',
  estimatedDuration: 45,
  difficulty: 'intermediate',
  category: 'strength',
  exercises: const [],
);

class _Harness {
  _Harness() {
    sessionId = store.seedSession(
      userId: _userId,
      workoutId: _workout.id,
      workoutTitle: _workout.title,
    );
  }

  final store = InMemoryWorkoutSessionStore();
  late final String sessionId;

  String get status => store.rowById(sessionId)!['status'] as String;
}

Future<void> _pump(WidgetTester tester, _Harness h, double width) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, _height);
  addTearDown(tester.view.reset);

  // The session Home shows: long unfinished, so its elapsed line is at its widest.
  final session = WorkoutSessionRecord(
    id: h.sessionId,
    userId: _userId,
    workoutId: _workout.id,
    workoutTitle: _workout.title,
    status: WorkoutSessionStatus.inProgress,
    startedAt: DateTime.now().subtract(const Duration(days: 37)),
  );

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      // The same shape as Home: inset 16 each side, the banner above an Expanded
      // hero, no scrolling.
      builder: (_, __) => const Scaffold(
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResumeWorkoutBanner(),
              Expanded(key: Key('hero'), child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/active-workout',
      builder: (_, __) => const Text('active workout screen'),
    ),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      activeSessionProvider.overrideWith((ref) async => session),
      workoutSessionStoreProvider.overrideWithValue(h.store),
      assignedWorkoutsProvider.overrideWith((ref) async => [_workout]),
      workoutsProvider.overrideWithValue(const []),
    ],
    child: MaterialApp.router(
      theme: TwelveCircleTheme.theme,
      routerConfig: router,
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Finder get _resume => find.widgetWithText(ElevatedButton, 'Resume');
Finder get _close => find.widgetWithIcon(IconButton, Icons.close_rounded);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final width in _widths) {
    group('at ${width.toInt()} wide', () {
      testWidgets('the banner lays out without a layout error', (tester) async {
        await _pump(tester, _Harness(), width);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Resume and close are fully on screen', (tester) async {
        await _pump(tester, _Harness(), width);

        final screen = Offset.zero & Size(width, _height);
        for (final control in [_resume, _close]) {
          final rect = tester.getRect(control);
          expect(rect.width, greaterThan(0));
          expect(screen.contains(rect.topLeft), isTrue, reason: '$rect');
          expect(screen.contains(rect.bottomRight), isTrue, reason: '$rect');
        }
      });

      // The test font draws every glyph a full em wide, far wider than the real
      // one, so these two hold only down to 360. Real-font behaviour below that is
      // a release-build check, not something this font can show.
      testWidgets('the text keeps a usable width', (tester) async {
        await _pump(tester, _Harness(), width);

        final title = tester.getSize(find.text('Resume Workout?'));
        expect(title.width, greaterThan(40), reason: '$title');
      }, skip: width < 360);

      testWidgets('the banner leaves the hero most of the screen', (tester) async {
        await _pump(tester, _Harness(), width);

        final hero = tester.getSize(find.byKey(const Key('hero')));
        expect(hero.height, greaterThan(_height / 2), reason: '$hero');
      }, skip: width < 360);
    });
  }

  testWidgets('tapping Resume opens the active workout', (tester) async {
    final h = _Harness();
    await _pump(tester, h, 375);

    await tester.tap(_resume);
    await tester.pumpAndSettle();

    expect(find.text('active workout screen'), findsOneWidget);
    expect(h.status, WorkoutSessionStatus.inProgress,
        reason: 'Resuming must not change the session.');
  });

  testWidgets('tapping close abandons the session and hides the banner',
      (tester) async {
    final h = _Harness();
    await _pump(tester, h, 375);

    await tester.tap(_close);
    await tester.pumpAndSettle();

    expect(find.text('Resume Workout?'), findsNothing);
    expect(h.status, WorkoutSessionStatus.abandoned);
  });
}
