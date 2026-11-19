import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-38 (H-06, coach half) — a coach's pending-request list never asks for
// a requester's health data, and shows who is asking.
//
// `getPendingRequests` read `user_profiles` for `email, fitness_goal,
// weight_kg` of people who are NOT this coach's clients yet. The live policy
// on user_profiles is `id = auth.uid() OR is_active_coach_of(id)`, so for a
// PENDING requester that read returns no row at all: the health columns were
// requested and never arrived, and every card on the Requests tab said
// "New Client" with no name and no avatar.
//
// The fake below APPLIES that policy (no user_profiles row for a requester who
// is not an active client) and serves `public_profiles` (migrations 101/110:
// any user, no email, no health columns) for everyone.
//
// HOW TO SEE IT FAIL: `git checkout 6f8918f -- lib/features/coach/data/
// coach_relationship_service.dart` — the select names fitness_goal, weight_kg
// and email, and the card reads "New Client".

const _coach = '00000000-0000-4000-8000-0000000c0e38';
const _requester = '00000000-0000-4000-8000-00000000ae38';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _coach,
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
          'id': _coach,
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

/// Columns a coach must not request about someone who is not their client.
const _healthOrContact = {
  'email', 'fitness_goal', 'weight_kg', 'weight_goal_kg', 'height_cm',
  'date_of_birth', 'gender', 'parq_answers', 'risk_level', 'risk_score',
  'risk_flags', 'medical_conditions', 'has_injuries', 'injury_locations',
  'injury_description', 'experience_level', 'training_location', 'phone',
};

class _PolicyServer extends http.BaseClient {
  /// `table -> select=` of every GET.
  final reads = <String, List<String>>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final table = request.url.path.split('/').last;
    final select = request.url.queryParameters['select'] ?? '*';
    reads.putIfAbsent(table, () => []).add(select);
    switch (table) {
      case 'coach_client_relationships':
        return _json(request, [
          {
            'id': 'rel-1',
            'client_id': _requester,
            'request_message': 'Hi — can you help me train for a 10k?',
            'pending_at': '2026-11-18T09:00:00Z',
            'initiated_by': 'client',
          },
        ]);
      case 'user_profiles':
        // Live policy: (id = auth.uid()) OR is_active_coach_of(id). The
        // requester is PENDING, so RLS filters their row out: 200 [].
        return _json(request, []);
      case 'public_profiles':
        final row = <String, Object?>{
          'id': _requester,
          'first_name': 'Jordan',
          'last_name': 'Rivers',
          'avatar_url': 'https://example.test/a.png',
          'role': 'client',
        };
        return _json(request, [
          {
            for (final c in select.split(',').map((c) => c.trim()))
              if (row.containsKey(c)) c: row[c],
          },
        ]);
    }
    return _json(request, []);
  }

  http.StreamedResponse _json(http.BaseRequest request, Object? body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: request, headers: {'content-type': 'application/json'});
}

void main() {
  final server = _PolicyServer();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(server.reads.clear);

  test(
      'getPendingRequests requests no health or contact column about a '
      'requester, from any table', () async {
    await CoachRelationshipService().getPendingRequests(_coach);
    for (final MapEntry(key: table, value: selects) in server.reads.entries) {
      for (final s in selects) {
        final cols = s.split(',').map((c) => c.trim()).toSet();
        expect(s, isNot('*'), reason: '$table select=* reads every column');
        expect(cols.intersection(_healthOrContact), isEmpty,
            reason: '$table select=$s asks for a pending requester\'s '
                'health/contact data');
      }
    }
  });

  test(
      'under the live policy the requester\'s name and avatar still arrive — '
      'from public_profiles', () async {
    final rows = await CoachRelationshipService().getPendingRequests(_coach);
    expect(rows, hasLength(1));
    final profile = rows.single['profile'] as Map;
    expect(profile['first_name'], 'Jordan');
    expect(profile['last_name'], 'Rivers');
    expect(profile['avatar_url'], 'https://example.test/a.png');
    expect(rows.single['id'], 'rel-1', reason: 'the relationship row is kept');
    expect(server.reads.containsKey('public_profiles'), isTrue);
  });

  testWidgets(
      'the Requests tab names the requester instead of "New Client"',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async => const []),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        coachNotificationsProvider
            .overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        // The REAL service against the policy-applying fake.
        pendingRequestsProvider.overrideWith(
            (ref) => CoachRelationshipService().getPendingRequests(_coach)),
        sentInvitesProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    ));
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.tap(find.textContaining('Requests').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.text('Pending Requests'), findsOneWidget);
    expect(find.text('Jordan Rivers'), findsOneWidget);
    expect(find.text('New Client'), findsNothing,
        reason: 'the coach must see who is asking before accepting');
  });
}
