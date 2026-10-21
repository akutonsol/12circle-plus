// Live service-layer integration test.
// Drives the REAL service classes against the live Supabase dev instance and
// asserts their side effects (12 Circle Score awarding + in-app notifications)
// that only run inside the Flutter app — i.e. the half the headless REST
// harness (tool/live_integration_test.dart) cannot reach.
//
// Run on the macOS desktop target (real network + secure storage):
//   flutter test integration_test/service_logic_test.dart -d macos
//
// Requires APPLY_MISSING.sql to have been applied and the seeded test accounts.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/constants/app_constants.dart';
import 'package:circle_fitness/features/nutrition/data/nutrition_service.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';

const _clientEmail = 'test@12circle.app';
const _clientPass = 'Test1234!';

SupabaseClient get _db => Supabase.instance.client;
String get _uid => _db.auth.currentUser!.id;
String _today() => DateTime.now().toIso8601String().split('T')[0];

Future<int> _notifCount(String recipientId, String type) async {
  final rows = await _db
      .from('notifications')
      .select('id')
      .eq('recipient_id', recipientId)
      .eq('type', type);
  return (rows as List).length;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
    await _db.auth.signInWithPassword(email: _clientEmail, password: _clientPass);
    expect(_db.auth.currentUser, isNotNull, reason: 'client must sign in');
  });

  tearDownAll(() async {
    await _db.auth.signOut();
  });

  // ── SCR-002: logging a meal awards 12 Circle Score nutrition points ───────
  testWidgets('NutritionService.logMeal awards nutrition score', (_) async {
    // Reset today's nutrition points to isolate the assertion.
    await _db.from('daily_scores').upsert({
      'user_id': _uid, 'score_date': _today(),
      'workout_points': 0, 'nutrition_points': 0, 'habits_points': 0,
      'checkin_points': 0, 'community_points': 0, 'total_score': 0,
    }, onConflict: 'user_id,score_date');

    await NutritionService().logMeal(
      mealType: 'breakfast',
      foodName: '__itest oats',
      calories: 600, protein: 60, carbs: 80, fat: 15,
      servingSize: 100, servingUnit: 'g',
    );

    final row = await _db
        .from('daily_scores')
        .select('nutrition_points')
        .eq('user_id', _uid).eq('score_date', _today())
        .single();
    final pts = (row['nutrition_points'] as num).toInt();
    expect(pts, greaterThan(0),
        reason: 'logMeal should award nutrition points (SCR-002)');

    // cleanup the test meal
    await _db.from('nutrition_logs')
        .delete().eq('user_id', _uid).eq('food_name', '__itest oats');
  });

  // ── MSG-003 ─────────────────────────────────────────────────────────────
  //
  // F-25: THIS TEST USED TO ASSERT SOMETHING IT COULD NOT OBSERVE.
  //
  // It counted the RECIPIENT's notifications — `_notifCount(coachId, …)` —
  // from the SENDER's session. `notifications` carries
  // `recipients read own notifications … USING (recipient_id = auth.uid())`
  // (003/004), so that query returns 0 before and 0 after, for any sender,
  // forever. `after - before` was always 0 and the assertion `== 1` was
  // unsatisfiable.
  //
  // It therefore said nothing about whether the trigger fires. Worse: **the
  // only way it could ever have gone green is if `notifications` leaked rows
  // across users.** A test whose passing condition is a privacy defect is not
  // a weaker test, it is a wrong one.
  //
  // Verifying the recipient's side needs the RECIPIENT's session, and this
  // file signs in as one fixture whose coach's credentials it does not have.
  // So the recipient-side half is NOT claimed here — it is recorded as open in
  // docs/QA_EVIDENCE.md rather than asserted from a session that cannot see it.
  //
  // What the sender CAN honestly observe is below, and it is the regression
  // the test was originally written for: the Dart-side duplicate insert is
  // gone and the notification is left to the DB trigger.
  testWidgets('MessagingService.sendMessage leaves notification to the trigger',
      (_) async {
    final convId = await MessagingService().getOrCreateClientCoachConversation();
    expect(convId, isNotNull, reason: 'client must have a coach conversation');

    // The sender must not notify themselves — the "not two" half of MSG-003,
    // and the half this session can actually see.
    final selfBefore = await _notifCount(_uid, 'message');
    final ok = await MessagingService()
        .sendMessage(conversationId: convId!, content: '__itest ping');
    expect(ok, isTrue);
    await Future.delayed(const Duration(milliseconds: 600));
    expect(await _notifCount(_uid, 'message'), selfBefore,
        reason: 'the sender must not be notified of their own message');

    // And the message really was written.
    final rows = await _db
        .from('messages')
        .select('id')
        .eq('conversation_id', convId)
        .eq('content', '__itest ping');
    expect((rows as List), isNotEmpty);

    // cleanup test message
    await _db.from('messages')
        .delete().eq('conversation_id', convId).eq('content', '__itest ping');
  });

  testWidgets('WeeklyCheckinService.submitWeeklyCheckin scores + notifies coach',
      (_) async {
    // F-25, second instance. This used to count the COACH's notifications from
    // the client's session and assert `after - before <= 1`. Under
    // `recipients read own notifications` both reads are 0, so the assertion
    // was `0 <= 1` — **green forever, whatever the app did**.
    //
    // The messaging test next door had the identical fault with the opposite
    // symptom: it asserted `== 1` and was red forever. One root cause, and the
    // green one is the more dangerous of the two, because nobody looks at it.
    //
    // What the client's own session can observe is asserted instead.
    final selfBefore = await _notifCount(_uid, 'checkin');

    // reset checkin points for a clean assertion
    await _db.from('daily_scores').upsert({
      'user_id': _uid, 'score_date': _today(),
      'workout_points': 0, 'nutrition_points': 0, 'habits_points': 0,
      'checkin_points': 0, 'community_points': 0, 'total_score': 0,
    }, onConflict: 'user_id,score_date');

    final ok = await WeeklyCheckinService().submitWeeklyCheckin(
      mood: 4, energy: 4, stress: 2, sleepHoursAvg: 7.5, notes: '__itest',
    );
    expect(ok, isTrue, reason: 'check-in should submit');

    final row = await _db.from('daily_scores')
        .select('checkin_points').eq('user_id', _uid).eq('score_date', _today())
        .single();
    expect((row['checkin_points'] as num).toInt(), greaterThan(0),
        reason: 'weekly check-in should award check-in points (SCR-004)');

    // The client must not be notified about their own check-in. Whether the
    // COACH was notified needs the coach's session, and this file does not
    // have one — recorded as open in docs/QA_EVIDENCE.md rather than asserted
    // from a session that cannot see it.
    await Future.delayed(const Duration(milliseconds: 600));
    expect(await _notifCount(_uid, 'checkin'), selfBefore,
        reason: 'the client must not be notified of their own check-in');
  });
}
