import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-9 · Home › Rate Your Coach.
//
// The coach_reviews upsert did not ask for its row back, and every failure was
// `catch (_) { saving = false; }`: the spinner stopped and nothing was said.
// After it, the CLIENT re-read all reviews and PATCHed the COACH's
// user_profiles rating_avg / review_count — a write that can never take effect
// (no UPDATE right on another user's row, and migration 115 pins both columns
// for every authenticated caller; migration 045's trigger maintains them).
//
// HOW TO SEE IT FAIL: with the base commit's home_screen.dart (plus only the
// test hook) a 0-row or refused review shows no message, and a successful one
// still PATCHes user_profiles.
//
// Tests use the dialog's test hook rather than the whole dashboard: the dialog
// is a private function opened from deep inside HomeScreen.

const _uid = '00000000-0000-4000-8000-0000000f1092';
const _offline =
    "Couldn't submit your review — check your connection and try again.";
const _failed = "Couldn't submit your review — try again in a moment. "
    'If it keeps happening, contact support.';
const _thanks = 'Review submitted! Thank you.';

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

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
    server.reads['coach_reviews'] = [
      {'rating': 5},
      {'rating': 3},
    ];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> submit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => showRateCoachDialogForTest(context, 'coach-1'),
              child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Great sessions');
    await tester.tap(find.text('Submit'));
    await settle(tester);
  }

  List<String> reviewWrites() =>
      server.writes.where((w) => w.contains('/coach_reviews')).toList();
  List<String> profileWrites() =>
      server.writes.where((w) => w.contains('/user_profiles')).toList();

  testWidgets('a review that stored no row says so inside the dialog',
      (tester) async {
    server.mode = WriteMode.zeroRows;
    await submit(tester);

    expect(reviewWrites(), hasLength(1), reason: 'premise');
    expect(reviewWrites().single, contains('select=id'),
        reason: 'the upsert must ask for its row back');
    expect(find.text(_thanks), findsNothing);
    expect(_inDialog(_failed), findsOneWidget,
        reason: 'THE defect: nothing was said');
    expect(find.text('Rate Your Coach'), findsOneWidget,
        reason: 'the dialog stays open');
    expect(find.text('Submit'), findsOneWidget, reason: 'saving was reset');
    expect(reported, isNotEmpty);
  });

  // U3. The error appears inside a dialog after Submit; a screen-reader user
  // only learns of it if it is in the semantics tree AND announced on change
  // (a live region). Pins the `Semantics(liveRegion: true)` wrapper.
  testWidgets('the error is exposed to semantics as a live region',
      (tester) async {
    final semantics = tester.ensureSemantics();
    server.mode = WriteMode.zeroRows;
    await submit(tester);
    expect(_inDialog(_failed), findsOneWidget, reason: 'premise');

    final node = tester.getSemantics(_inDialog(_failed));
    expect(node.label, contains(_failed),
        reason: 'the error text is not in the semantics tree');
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue,
        reason: 'the error is not announced when it appears');
    semantics.dispose();
  });

  testWidgets('a refused review shows the support wording, not the connection',
      (tester) async {
    server.mode = WriteMode.serverError;
    await submit(tester);
    expect(_inDialog(_failed), findsOneWidget);
    expect(find.text(_offline), findsNothing);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a network failure says check your connection', (tester) async {
    server.mode = WriteMode.network;
    await submit(tester);
    expect(_inDialog(_offline), findsOneWidget);
    expect(find.text('Rate Your Coach'), findsOneWidget);
  });

  testWidgets(
      'control: a stored review closes with thanks — and no longer writes '
      "the coach's profile", (tester) async {
    await submit(tester);
    expect(find.text(_thanks), findsOneWidget);
    expect(find.text('Rate Your Coach'), findsNothing);
    expect(
        reviewWrites().single,
        allOf(contains('"coach_id":"coach-1"'), contains('"rating":5'),
            contains('"review_text":"Great sessions"')),
        reason: 'what is written is unchanged');
    expect(profileWrites(), isEmpty,
        reason: 'the client-side rating_avg recompute could never take effect '
            '(RLS + migration 115) — the 045 trigger owns the aggregate');
    expect(reported, isEmpty);
  });
}
