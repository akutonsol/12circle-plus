import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/notifications/notification_watcher.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/coach_checkin_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The weekly check-in loop, as the beta-readiness audit found it on facb92f:
//   * C1 — every way into the coach's review screen arrived with nothing
//     selected, so it said "No check-in selected" and a coach could never open
//     a client's check-in. PD7: open the oldest submitted one.
//   * C4 — the review summary read the legacy `energy` / `sleep_hours_avg`
//     columns; the writer stores `energy_level` / `sleep_hours`.
//   * C2/N1 — the client never wrote `coach_id`, so `trg_notify_coach_on_checkin`
//     (004) returned early and no coach was ever told a check-in arrived.
//   * C9 — `submitted_at` and `reviewed_at` went out as local time with no zone.
//   * C5 — a check-in that saved was reported "Failed to save" when only the
//     points that follow it failed.
//   * C6 — a failed queue read came back as an empty queue.
//   * C8 — on bb00a0e the queue was cached for the session and only the coach
//     dashboard re-read it, so a coach who opened Check-ins after a client
//     submitted was shown `1 of 1` while QA held two.
//
// The service tests drive the real service, signed in, with only the network
// substituted. The screen tests drive the real review screen.

const _uid = '00000000-0000-4000-8000-0000000c4c1e';
const _coach = '00000000-0000-4000-8000-00000000c0ac';
const _coach2 = '00000000-0000-4000-8000-00000000c0a2';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// gotrue reads `sub` and `exp` from the body without a round-trip while the
/// token is unexpired, and never verifies the signature on the client.
String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
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

/// Answers by path and remembers what was asked. A path in [failing] answers
/// 500; [bodies] gives a GET its rows; everything else answers `[]`.
class _Server extends http.BaseClient {
  final requests = <http.Request>[];
  final bodies = <String, Object>{};
  final failing = <String>{};

  http.Request? last(String method, String path) {
    for (final r in requests.reversed) {
      if (r.method == method && r.url.path == path) return r;
    }
    return null;
  }

  void reset() {
    requests.clear();
    bodies.clear();
    failing.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    final path = request.url.path;
    final fail = failing.contains(path);
    final body = fail
        ? {'message': 'simulated failure', 'code': 'XX000'}
        : (request.method == 'GET' ? bodies[path] ?? const [] : const []);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      fail ? 500 : 200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

const _checkins = '/rest/v1/weekly_checkins';
const _relationships = '/rest/v1/coach_client_relationships';

Map<String, dynamic> _sent(_Server s) =>
    jsonDecode(s.last('POST', _checkins)!.body) as Map<String, dynamic>;

Future<bool> _submit() => WeeklyCheckinService().submitWeeklyCheckin(
    mood: 4, energy: 3, stress: 2, sleepHoursAvg: 7.5, notes: 'ok');

// ── Review screen harness ────────────────────────────────────────────────────

class _NoSendService implements WeeklyCheckinService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> _row(String id, String first, {Map<String, dynamic>? extra}) => {
      'id': id,
      'week_number': 45,
      'status': 'submitted',
      'user_profiles': {'first_name': first, 'last_name': 'Osei'},
      ...?extra,
    };

Future<void> _openReview(
  WidgetTester tester, {
  required Future<List<Map<String, dynamic>>> Function() queue,
  Map<String, dynamic>? selected,
}) async {
  final container = ProviderContainer(overrides: [
    coachSubmittedCheckinsProvider.overrideWith((ref) => queue()),
    selectedCoachCheckinProvider.overrideWith((ref) => selected),
    weeklyCheckinServiceProvider.overrideWithValue(_NoSendService()),
    currentUserDisplayNameProvider.overrideWithValue('Coach Nadia'),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/coach-checkin-review', routes: [
    GoRoute(
      path: '/coach-checkin-review',
      builder: (_, __) => const CoachCheckinReviewScreen(),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

/// The coach's queue as the server holds it, which a test changes between
/// visits. [gate], when set, holds the next read open.
class _QueueService implements WeeklyCheckinService {
  final rows = <Map<String, dynamic>>[];
  Completer<void>? gate;

  @override
  Future<List<Map<String, dynamic>>> getSubmittedCheckinsForCoach() async {
    await gate?.future;
    return List.of(rows);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The real queue and selection providers, under two shell routes the way the
/// app has them: leaving Check-ins for Clients and coming back is a `go` each
/// way. Clients is a stand-in, so nothing here is the dashboard re-reading.
Future<({ProviderContainer container, GoRouter router})> _openCheckins(
    WidgetTester tester, _QueueService service) async {
  final container = ProviderContainer(overrides: [
    weeklyCheckinServiceProvider.overrideWithValue(service),
    currentUserDisplayNameProvider.overrideWithValue('Coach Nadia'),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/coach-checkin-review', routes: [
    ShellRoute(
      builder: (_, __, child) => child,
      routes: [
        GoRoute(
          path: '/coach-dashboard',
          builder: (_, __) => const Scaffold(body: Text('Clients')),
        ),
        GoRoute(
          path: '/coach-checkin-review',
          builder: (_, __) => const CoachCheckinReviewScreen(),
        ),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

Future<void> _leaveAndReopen(WidgetTester tester, GoRouter router) async {
  router.go('/coach-dashboard');
  await tester.pumpAndSettle();
  expect(find.text('Clients'), findsOneWidget);
  router.go('/coach-checkin-review');
  await tester.pumpAndSettle();
}

late _Server _server;

void main() {
  setUpAll(() async {
    _server = _Server();
    await Supabase.initialize(
      // Unroutable, and every request answered and recorded by the server above.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        autoRefreshToken: false,
      ),
      debug: false,
    );
  });

  setUp(() => _server.reset());

  group('C2/N1 the first submission names the coach', () {
    test('with no row this week and one active coach, coach_id is that coach', () async {
      _server.bodies[_relationships] = [
        {'coach_id': _coach},
      ];

      expect(await _submit(), isTrue);
      expect(_sent(_server)['coach_id'], _coach,
          reason: 'without coach_id the notify trigger returns early and the '
              'coach is never told a check-in arrived');
    });

    test('with two active coaches, no coach is guessed', () async {
      _server.bodies[_relationships] = [
        {'coach_id': _coach},
        {'coach_id': _coach2},
      ];

      expect(await _submit(), isTrue);
      expect(_sent(_server).containsKey('coach_id'), isFalse,
          reason: 'with more than one active coach there is no single right '
              'answer; naming either one would notify a coach at random');
    });

    test('a resubmission leaves coach_id alone', () async {
      // The authorship trigger (114) refuses a client changing coach_id on
      // UPDATE, so sending it again would fail the whole resubmission.
      _server.bodies[_checkins] = [
        {'id': 'existing'},
      ];
      _server.bodies[_relationships] = [
        {'coach_id': _coach},
      ];

      expect(await _submit(), isTrue);
      expect(_sent(_server).containsKey('coach_id'), isFalse);
    });

    test('a failed coach lookup still saves the check-in, without coach_id', () async {
      _server.failing.add(_relationships);

      expect(await _submit(), isTrue);
      expect(_sent(_server).containsKey('coach_id'), isFalse);
    });
  });

  group('C9 check-in times carry their zone', () {
    test('submitted_at goes out as UTC', () async {
      await _submit();
      expect(_sent(_server)['submitted_at'], endsWith('Z'),
          reason: 'a timestamptz column reads a zoneless time as UTC');
    });

    test('reviewed_at goes out as UTC', () async {
      _server.bodies[_checkins] = [
        {'user_id': _uid},
      ];

      await WeeklyCheckinService().submitCoachFeedback(
          checkinId: 'c1', message: 'Nice week', recommendations: const [], coachName: 'Coach');

      final patch = jsonDecode(_server.last('PATCH', _checkins)!.body) as Map<String, dynamic>;
      expect(patch['reviewed_at'], endsWith('Z'));
    });
  });

  group('C5 a saved check-in is reported as saved', () {
    test('points failing after the save does not report the save as failed', () async {
      _server.failing.addAll({'/rest/v1/daily_scores', '/rest/v1/rpc/award_points'});

      expect(await _submit(), isTrue,
          reason: 'the check-in row was written; telling the client "Failed to '
              'save" invites a resubmission of something already saved');
      expect(_server.last('POST', _checkins), isNotNull);
    });

    test('the check-in itself failing is still reported', () async {
      _server.failing.add(_checkins);

      expect(await _submit(), isFalse);
    });
  });

  group('C6 a failed queue read is not an empty queue', () {
    test('the service raises instead of returning nothing', () async {
      _server.failing.add(_checkins);

      await expectLater(
          WeeklyCheckinService().getSubmittedCheckinsForCoach(), throwsA(anything));
    });

    testWidgets('with nothing selected, the screen states the failure', (tester) async {
      await _openReview(tester,
          queue: () => Future<List<Map<String, dynamic>>>.error(Exception('network')));

      expect(find.textContaining("ouldn't load your review queue"), findsOneWidget);
      expect(find.text('No check-in selected'), findsNothing);
    });
  });

  group('C1 the review screen opens the oldest submitted check-in', () {
    testWidgets('with nothing selected, the first in the queue is open', (tester) async {
      await _openReview(tester,
          queue: () async => [_row('a', 'Amara'), _row('b', 'Tomas')]);

      expect(find.text('No check-in selected'), findsNothing,
          reason: 'every way into this screen arrives with nothing selected');
      expect(find.textContaining('Amara'), findsWidgets);
      expect(find.textContaining('1 of 2'), findsOneWidget);
    });

    testWidgets('an empty queue still says there is nothing to review', (tester) async {
      await _openReview(tester, queue: () async => const []);

      expect(find.text('No check-in selected'), findsOneWidget);
    });
  });

  group('C8 reopening Check-ins reads the queue again', () {
    final older = _row('a', 'Amara', extra: {'week_number': 39});
    final newer = _row('b', 'Tomas');

    testWidgets('a check-in submitted while away is there on return', (tester) async {
      // Real-build QA on bb00a0e: Jordan submitted, QA held two, and the coach
      // opened Check-ins to `1 of 1`.
      final service = _QueueService()..rows.add(older);
      final app = await _openCheckins(tester, service);
      expect(find.textContaining('1 of 1'), findsOneWidget);

      service.rows.add(newer);
      await _leaveAndReopen(tester, app.router);

      expect(find.textContaining('1 of 2'), findsOneWidget,
          reason: 'the coach was shown the queue as it was before the client '
              'submitted');
      expect(find.textContaining('Amara'), findsWidgets,
          reason: 'PD7: the oldest submitted check-in opens first');

      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 of 2'), findsOneWidget);
      expect(find.textContaining('Tomas'), findsWidgets);
    });

    testWidgets('where Next had reached is not where the next visit opens',
        (tester) async {
      // PD7 is "every way in opens the oldest". A selection kept from the last
      // visit is a copy of a row as it was then, and after a send it is a
      // check-in that is no longer in the queue at all.
      final service = _QueueService()..rows.addAll([older, newer]);
      final app = await _openCheckins(tester, service);
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 of 2'), findsOneWidget);

      await _leaveAndReopen(tester, app.router);

      expect(find.textContaining('1 of 2'), findsOneWidget);
      expect(find.textContaining('Amara'), findsWidgets);
    });

    testWidgets('a weekly_checkins notification re-reads the open queue in place',
        (tester) async {
      final service = _QueueService()..rows.add(older);
      final app = await _openCheckins(tester, service);
      expect(find.textContaining('1 of 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Half-written reply');

      service
        ..rows.add(newer)
        ..gate = Completer<void>();
      refreshForNotification('weekly_checkins', app.container.invalidate);
      await tester.pump();

      // While the re-read is in flight the coach keeps the check-in and the
      // reply they are writing; the screen does not drop to a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Half-written reply'), findsOneWidget);
      expect(find.textContaining('Amara'), findsWidgets);

      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('1 of 2'), findsOneWidget);
      expect(find.text('Half-written reply'), findsOneWidget);
    });
  });

  group('C4 the summary reads the canonical columns', () {
    testWidgets('energy_level and sleep_hours are shown', (tester) async {
      final row = _row('a', 'Amara', extra: {'energy_level': 4, 'sleep_hours': 7.5});
      await _openReview(tester, queue: () async => [row], selected: row);

      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('7.5 hrs'), findsOneWidget);
    });
  });
}
