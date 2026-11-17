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
