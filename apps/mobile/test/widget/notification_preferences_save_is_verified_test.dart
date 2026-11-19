import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/profile/presentation/notification_preferences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-39 · Profile › Notifications: a toggle is "saved" only when the server
// confirmed it.
//
// At 6f8918f `_saveToggle` sent `.update({field: value}).eq('id', uid)` with no
// `.select('id')`. A 0-row update (RLS filtered it) answers 204 exactly like a
// saved one, so the toggle stayed flipped and nothing was said. A thrown save
// left the toggle flipped too (the member sees a setting that is not stored)
// and said "Failed to save." — not the house voice, and never reported.
// Challenges/Community also announced "will now appear in your Activity feed"
// before the save had answered.
//
// HOW TO SEE IT FAIL: with 6f8918f's notification_preferences_screen.dart the
// 0-row and throw tests find the toggle still flipped, no house-voice message
// and nothing reported, and the PATCH carries no `select=id`.

const _uid = '00000000-0000-4000-8000-0000000f1039';
const _offline = "Couldn't save this notification setting — check your "
    'connection and try again.';
const _failed = "Couldn't save this notification setting — try again in a "
    'moment. If it keeps happening, contact support.';
const _challengesOn = 'Challenges will now appear in your Activity feed';

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
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider.overrideWith((ref) async => {
              'notif_workout_reminders': true,
              'notif_checkin_reminders': true,
              'notif_coach_messages': true,
              'notif_progress_updates': true,
              'notif_challenges': false,
              'notif_community': false,
            }),
      ],
      child: const MaterialApp(home: NotificationPreferencesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// The toggle in the row titled [title] (its AnimatedAlign shows the value).
  bool isOn(WidgetTester tester, String title) {
    final row = find.ancestor(of: find.text(title), matching: find.byType(Row)).first;
    final align = tester.widget<AnimatedAlign>(
        find.descendant(of: row, matching: find.byType(AnimatedAlign)));
    return align.alignment == Alignment.centerRight;
  }

  Future<void> tapToggle(WidgetTester tester, String title) async {
    final row = find.ancestor(of: find.text(title), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byType(AnimatedAlign)));
    await tester.pumpAndSettle();
  }

  testWidgets('a 0-row save puts the toggle back and says so', (tester) async {
    await open(tester);
    expect(isOn(tester, 'Workout Reminders'), isTrue, reason: 'premise');
    server.mode = WriteMode.zeroRows;
    await tapToggle(tester, 'Workout Reminders');

    expect(server.writes.single, contains('select=id'),
        reason: 'the save must ask for its row back to see a 0-row update');
    expect(server.writes.single, contains('"notif_workout_reminders":false'),
        reason: 'the key written is unchanged');
    expect(isOn(tester, 'Workout Reminders'), isTrue,
        reason: 'THE defect: the toggle stayed off though nothing was stored');
    expect(find.text(_failed), findsOneWidget);
    expect(find.textContaining('Failed to save'), findsNothing);
    expect(reported.single.origin, 'NotificationPreferencesScreen._saveToggle');
  });

  testWidgets('a server error puts the toggle back, says try again, no '
      'connection hint and no exception text', (tester) async {
    await open(tester);
    server.mode = WriteMode.serverError;
    await tapToggle(tester, 'Coach Messages');
    expect(isOn(tester, 'Coach Messages'), isTrue);
    expect(find.text(_failed), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.textContaining('refused'), findsNothing);
    expect(reported, hasLength(1));
  });

  testWidgets('a connection failure puts the toggle back and gives the '
      'connection hint', (tester) async {
    await open(tester);
    server.mode = WriteMode.network;
    await tapToggle(tester, 'Progress Updates');
    expect(isOn(tester, 'Progress Updates'), isTrue);
    expect(find.text(_offline), findsOneWidget);
    expect(reported, hasLength(1));
  });

  testWidgets('a failed Challenges save does not announce the feed change',
      (tester) async {
    await open(tester);
    server.mode = WriteMode.zeroRows;
    await tapToggle(tester, 'Challenges');
    expect(isOn(tester, 'Challenges'), isFalse, reason: 'put back to off');
    expect(find.text(_challengesOn), findsNothing,
        reason: 'it was announced before the save answered');
    expect(find.text(_failed), findsOneWidget);
  });

  // ── Controls ──────────────────────────────────────────────────────────────

  testWidgets('control: a confirmed save keeps the toggle, says nothing '
      'wrong, reports nothing', (tester) async {
    await open(tester);
    await tapToggle(tester, 'Check-in Reminders');
    expect(isOn(tester, 'Check-in Reminders'), isFalse);
    expect(server.writes.single, contains('"notif_checkin_reminders":false'));
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets('control: a confirmed Challenges save still announces the feed',
      (tester) async {
    await open(tester);
    await tapToggle(tester, 'Challenges');
    expect(isOn(tester, 'Challenges'), isTrue);
    expect(find.text(_challengesOn), findsOneWidget);
  });
}
