import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-9 · Intake › resume progress.
//
// `_saveProgress` writes the step (phase 1) and the answers so far (phase 2)
// on every step and when the app is backgrounded. Both were `catch (_) {}`
// with no row check, so a refused or 0-row write lost the person's resume
// point and nothing said so — they could leave believing they could pick up
// where they were.
//
// Now a failed or 0-row save is reported and the person is told ONCE
// (non-blocking SnackBar) until a save succeeds again. Moving on is never
// blocked and what is written is unchanged.
//
// HOW TO SEE IT FAIL: with the base commit's intake_flow_screen.dart no notice
// appears and the PATCHes carry no `select=id`.

const _uid = '00000000-0000-4000-8000-0000000f1094';
const _notice = "Your progress couldn't be saved — you may need to redo this "
    'step if you leave.';

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.reads['user_profiles'] = {
      'id': _uid,
      'onboarding_step': 0,
      'first_name': 'Ana',
      'last_name': 'Lee',
    };
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: IntakeFlowScreen()),
    ));
    await settle(tester);
    expect(find.text('Get Started'), findsWidgets, reason: 'premise: step 0');
  }

  /// Leave the SnackBar's time on screen run out.
  Future<void> outlastSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  /// One more `_saveProgress` call, as the app losing focus fires it
  /// (resumed → inactive → resumed is the only legal one-step round trip).
  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // supabase_flutter restarts gotrue's 10 s auto-refresh ticker on resume;
    // inside the fake clock it would outlive the test.
    Supabase.instance.client.auth.stopAutoRefresh();
    await settle(tester);
  }

  List<String> stepWrites() => server.writes
      .where((w) => w.startsWith('PATCH') && w.contains('"onboarding_step"'))
      .toList();

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!;

  testWidgets(
      'a 0-row progress save tells the person once — and does not stop them '
      'moving on', (tester) async {
    await open(tester);
    server.mode = WriteMode.zeroRows;
    await tester.tap(find.text('Get Started').first);
    await settle(tester);

    expect(stepWrites(), isNotEmpty, reason: 'premise: progress was saved');
    expect(stepWrites().every((w) => w.contains('select=id')), isTrue,
        reason: 'every progress write must ask for its row back:\n'
            '${stepWrites().join('\n')}');
    expect(find.text(_notice), findsOneWidget,
        reason: 'THE defect: the resume point was lost in silence');
    expect(reported, isNotEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    expect(page(tester), 1.0, reason: 'moving to the next step is not blocked');

    // Further failing saves do NOT repeat the notice.
    await outlastSnackBar(tester);
    expect(find.text(_notice), findsNothing, reason: 'premise: it went away');
    await background(tester);
    await outlastSnackBar(tester);
    expect(find.text(_notice), findsNothing,
        reason: 'not on every step after the first');
  });

  testWidgets(
      'a refused save notifies too; after a save succeeds, a fresh '
      'failure is told again', (tester) async {
    await open(tester);
    server.mode = WriteMode.serverError;
    await background(tester);
    expect(find.text(_notice), findsOneWidget);
    await outlastSnackBar(tester);

    server.mode = WriteMode.oneRow;
    await background(tester);
    expect(find.text(_notice), findsNothing, reason: 'a save that worked');

    server.mode = WriteMode.network;
    await background(tester);
    expect(find.text(_notice), findsOneWidget,
        reason: 'progress stopped being saved again, so say so again');
    await outlastSnackBar(tester);
  });

  // U5. The notice was a fixed SnackBar along the bottom edge — exactly where
  // every step's Continue sits — so the tap meant to move on landed on the
  // notice. It now floats clear of the bottom bar.
  testWidgets(
      'the step\'s forward control stays visible and tappable while the '
      'notice shows', (tester) async {
    await open(tester);
    // Step 0's "Get Started" is the forward control that is always enabled
    // (step 1's Continue needs a date of birth from a picker). Every step's
    // forward control sits in the same bottom band.
    server.mode = WriteMode.zeroRows;
    await background(tester);
    expect(find.text(_notice), findsOneWidget, reason: 'premise: it shows');
    expect(page(tester), 0.0, reason: 'premise: still on step 0');

    final next = find.text('Get Started').first;
    // The visible card, not the SnackBar widget (whose rect includes its
    // transparent margin, which taps pass through — checked below).
    final notice = tester.getRect(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first);
    final button = tester.getRect(next);
    expect(notice.overlaps(button), isFalse,
        reason: 'the notice covers the control: notice=$notice '
            'control=$button');
    expect(notice.bottom, lessThanOrEqualTo(1200 - 110),
        reason: 'clear of the tallest bottom bar (~110 px)');

    final hits = tester
        .hitTestOnBinding(tester.getCenter(next))
        .path
        .map((e) => e.target)
        .toList();
    expect(hits.contains(tester.renderObject(next)), isTrue,
        reason: 'the control is not hit-testable under the notice');

    await tester.tap(next);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_notice), findsOneWidget,
        reason: 'premise: tapped while the notice was still up');
    expect(page(tester), 1.0, reason: 'the tap moved on');
    await outlastSnackBar(tester);
  });

  testWidgets('control: saves that store their row say nothing',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Get Started').first);
    await settle(tester);
    expect(stepWrites(), isNotEmpty);
    expect(stepWrites().first,
        contains('"onboarding_step":1,"onboarding_complete":false'),
        reason: 'what is written is unchanged');
    expect(find.text(_notice), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(reported, isEmpty);
  });
}
