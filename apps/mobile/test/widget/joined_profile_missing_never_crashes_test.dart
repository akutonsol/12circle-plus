import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart' hide heldFor, ownedRead;
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_business_screen.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/still_reading.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-41 — a list joined to a profile never crashes when that profile row
// does not come back (deleted account, or a row RLS does not let us read).
//
// Each producer below joined the profile client-side and fell back to an
// UNTYPED `?? {}` / `?? const {}`. The surrounding map's value type is
// `dynamic`, so the literal was inferred as Map<dynamic, dynamic>, and every
// consumer's `row['profile'] as Map<String, dynamic>?` threw a TypeError
// while building — the crash class P0-FL-38 fixed for the Requests tab.
//
//   A. ScoreService.getCoachLeaderboard -> coach dashboard Leaderboard tab
//      (rows and the "AI Risk Alert" list).
//   B. CoachBusinessScreen._load -> Team tab. NOT affected: its
//      `profileById` is built from a typed List<Map<String, dynamic>>, so the
//      `?? const {}` infers Map<String, dynamic>. Kept as a regression guard.
//   C. CoachRelationshipService.getMyActiveCoaches ('coach') -> cast in
//      settings_screen.dart:781 and manage_subscription_screen.dart:87/474.
//   D. coachReviewsProvider ('reviewer') -> cast in
//      coach_marketplace_screen.dart:552.
//
// C and D are proved at the producer: the consumers are private methods deep
// in large screens, and the only thing that can crash them is the runtime
// type this test checks (the exact `as Map<String, dynamic>?` they perform).
//
// HOW TO SEE IT FAIL: `git checkout df35d5f -- lib/features/coach/data/
// score_service.dart lib/features/coach/data/coach_relationship_service.dart
// lib/features/coach/domain/coach_provider.dart lib/features/dashboard/
// presentation/coach_dashboard_screen.dart` — A, C and D fail; B passes.

const _uid = '00000000-0000-4000-8000-0000000f1041';
const _ana = '00000000-0000-4000-8000-00000000a041'; // has a profile
const _gone = '00000000-0000-4000-8000-00000000b041'; // profile not returned
const _coachGone = '00000000-0000-4000-8000-00000000c041';
const _memberGone = '00000000-0000-4000-8000-00000000d041';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _uid,
        'role': 'authenticated',
        'exp': exp,
        'aud': 'authenticated'
      })}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// Answers every read; the joined profile of `_gone`, `_coachGone` and
/// `_memberGone` never comes back.
class _Server extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') return _json(request, []);
    final table = request.url.path.split('/').last;
    final select = request.url.queryParameters['select'] ?? '*';
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    switch (table) {
      case 'coach_client_relationships':
        if (select.contains('coach_id')) {
          return _json(request, [
            {'id': 'rel-c', 'coach_id': _coachGone, 'status': 'active'},
          ]);
        }
        return _json(request, [
          {'client_id': _ana},
          {'client_id': _gone},
        ]);
      case 'daily_scores':
        return _json(request, [
          {
            'user_id': _ana,
            'total_score': 80,
            'workout_points': 30,
            'nutrition_points': 30,
            'habits_points': 20,
            'score_date': '2026-11-22',
          },
          {
            'user_id': _gone,
            'total_score': 20,
            'workout_points': 10,
            'nutrition_points': 10,
            'habits_points': 0,
            'score_date': '2026-11-22',
          },
        ]);
      case 'user_profiles':
        // The signed-in coach's own row (CoachBusinessScreen). Its
        // `.maybeSingle()` read asks for a LIST filtered by id, so it is
        // matched by the filter too: answering it with another user's row
        // passed only while the screen never checked whose row it got
        // (P0-FL-54 now refuses a row that is not the signed-in coach's).
        if (single || request.url.queryParameters['id'] == 'eq.$_uid') {
          final row = {
            'id': _uid,
            'bio': 'Bio',
            'tagline': '',
            'pricing_monthly': 100,
            'years_experience': 3,
            'specialties': <String>[],
            'certifications': <String>[],
          };
          return _json(request, single ? row : [row]);
        }
        return _json(request, [
          {
            'id': _ana,
            'first_name': 'Ana',
            'last_name': 'Lee',
            'avatar_url': null,
          },
        ]);
      case 'coach_team_members':
        return _json(request, [
          {
            'id': 'tm-1',
            'coach_id': _uid,
            'member_id': _memberGone,
            'role': 'assistant',
          },
        ]);
      case 'coach_reviews':
        return _json(request, [
          {
            'rating': 5,
            'review_text': 'Great',
            'created_at': '2026-11-01T00:00:00Z',
            'client_id': _gone,
          },
        ]);
    }
    // public_profiles, team_member_profiles, ...: the row is not returned.
    return _json(request, []);
  }

  http.StreamedResponse _json(http.BaseRequest request, Object? body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: request, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  group('A. coach leaderboard', () {
    test('a client whose profile is not returned keeps their row, with a '
        'typed (empty) profile', () async {
      final rows = await ScoreService().getCoachLeaderboard(_uid);
      expect(rows.map((r) => r['user_id']), [_ana, _gone],
          reason: 'the row is never dropped');
      for (final r in rows) {
        expect(r['profile'], isA<Map<String, dynamic>>(),
            reason: 'the Leaderboard tab casts it to Map<String, dynamic>');
      }
      expect((rows.last['profile'] as Map<String, dynamic>), isEmpty);
      expect((rows.first['profile'] as Map)['first_name'], 'Ana');
    });

    testWidgets(
        'the Leaderboard tab builds, names the missing client "Client" in the '
        'row and in the risk alert', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          coachClientsProvider.overrideWith((ref) async => const []),
          clientCheckinsProvider.overrideWith((ref) async => const []),
          clientWorkoutLogsProvider.overrideWith((ref) async => const []),
          coachNotificationsProvider
              .overrideWith((ref) => Stream.value(const [])),
          currentUserProfileProvider.overrideWith((ref) async => null),
          currentUserDisplayNameProvider.overrideWithValue('Coach'),
          pendingRequestsProvider.overrideWith((ref) async => const []),
          sentInvitesProvider.overrideWith((ref) async => const []),
          coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
          // The REAL service against the fake.
          coachLeaderboardProvider.overrideWith(
              (ref) => ownedRead(
                  _uid, () => ScoreService().getCoachLeaderboard(_uid))),
          coachTriageSignalsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: CoachDashboardScreen()),
      ));
      for (var i = 0; i < 3; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      await t.ensureVisible(find.text('Leaderboard').first);
      await t.pump();
      await t.tap(find.text('Leaderboard').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(t.takeException(), isNull, reason: 'the tab builds');
      expect(find.text('Ana Lee'), findsOneWidget);
      expect(find.text('Client'), findsOneWidget,
          reason: 'the client without a profile is still on the board');
      expect(find.text('20 pts'), findsOneWidget);
      expect(find.text('• Client — 20 pts'), findsOneWidget,
          reason: 'the risk alert names them, not a blank');
      expect(find.text('No scores yet today'), findsNothing);
    });
  });

  group('B. coach business Team tab', () {
    testWidgets(
        'REGRESSION GUARD (passes on df35d5f): a team member whose roster '
        'profile is not returned keeps their row and the tab builds',
        (t) async {
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: CoachBusinessScreen()));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.text('Team'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(t.takeException(), isNull, reason: 'the tab builds');
      expect(find.text('assistant'), findsOneWidget,
          reason: 'the membership row is kept');
      expect(find.text('No team members yet'), findsNothing);
    });
  });

  test('C. getMyActiveCoaches: a coach whose public profile is not returned '
      'keeps the relationship with a typed (empty) coach map', () async {
    final rows = await CoachRelationshipService().getMyActiveCoaches();
    expect(rows.single['id'], 'rel-c');
    expect(rows.single['coach'], isA<Map<String, dynamic>>(),
        reason: 'settings/manage-subscription cast it to '
            'Map<String, dynamic>');
  });

  test('D. coachReviewsProvider: a reviewer whose public profile is not '
      'returned keeps the review with a typed (empty) reviewer map', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final rows = await c.read(coachReviewsProvider(_uid).future);
    expect(rows.single['review_text'], 'Great');
    expect(rows.single['reviewer'], isA<Map<String, dynamic>>(),
        reason: 'the marketplace review item casts it to '
            'Map<String, dynamic>');
  });
}
