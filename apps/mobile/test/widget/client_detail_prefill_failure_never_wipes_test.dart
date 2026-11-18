import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-12 — the coach's client page must never wipe a client's plan or habits
// after a failed read.
//
//  1. Set Nutrition Targets pre-filled the form with a `.then` and no error
//     handler: a failed read left it blank and Save wrote the blanks over the
//     client's plan.
//  2. Assign Habits did the same, and assignHabits switches OFF every active
//     habit before inserting, so Save wiped the client's habits.
//  3. clientHasPaidPlan turned a failed subscriptions read into `false`, and the
//     page said "Coaching services unlock once this client subscribes…".
//
// The REAL CoachProgramService runs against a fake PostgREST (500 or a dropped
// connection per table); the fake records every write.
//
// HOW TO SEE IT FAIL: check out e8ef987's client_detail_screen.dart and
// coach_program_service.dart — the failed-read tests find no failure notice,
// an enabled Save, and a write sent.

const _uid = '00000000-0000-4000-8000-0000000c0ac1';
const _clientId = '00000000-0000-4000-8000-00000000c1e1';

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

enum _Mode { ok, http500, network }

/// Reads of the three tables under test fail per [fail]; everything else
/// answers. Every non-GET is recorded in [writes].
class _Server extends http.BaseClient {
  final Map<String, _Mode> fail = {};
  Map<String, Object?>? plan;
  List<Map<String, Object?>> habits = [];
  bool subscribed = true;
  final List<String> writes = [];

  void reset() {
    fail.clear();
    plan = null;
    habits = [];
    subscribed = true;
    writes.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final table = path.split('/').last;
    if (request.method != 'GET' && request.method != 'HEAD') {
      writes.add('${request.method} $table');
      final body = request is http.Request ? request.body : '';
      if (table == 'assign_nutrition_plan') writes.add('body $body');
      return _json(request, request.method == 'POST' ? 201 : 200, []);
    }
    switch (fail[table] ?? _Mode.ok) {
      case _Mode.network:
        throw http.ClientException('Connection refused', request.url);
      case _Mode.http500:
        return _json(request, 500,
            {'code': 'XX000', 'message': 'boom', 'details': null, 'hint': null});
      case _Mode.ok:
        break;
    }
    final wantsObject =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final List<Object?> rows = switch (table) {
      'client_nutrition_plans' => [if (plan != null) plan],
      'client_habits' => habits,
      'subscriptions' => [
          if (subscribed) {'id': 'sub-1'}
        ],
      _ => [],
    };
    if (wantsObject) {
      // maybeSingle(): an absent row is PostgREST's 406 "0 rows".
      if (rows.isEmpty) {
        return _json(request, 406, {
          'code': 'PGRST116',
          'message': 'JSON object requested, multiple (or no) rows returned',
          'details': 'The result contains 0 rows',
          'hint': null,
        });
      }
      return _json(request, 200, rows.first);
    }
    return _json(request, 200, rows);
  }

  http.StreamedResponse _json(
          http.BaseRequest request, int status, Object? body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: request, headers: {'content-type': 'application/json'});
}

/// Client detail runs repeating animations, so `pumpAndSettle` would not return.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpPage(WidgetTester t) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 4000);
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/client',
    routes: [
      GoRoute(
        path: '/client',
        builder: (_, __) =>
            const ClientDetailScreen(clientId: _clientId, clientName: 'Jordan'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      // Only the page's unrelated reads are substituted; the service and the
      // paid-plan provider are real.
      clientDetailProvider(_clientId).overrideWith((ref) async => {
            'id': _clientId,
            'first_name': 'Jordan',
            'last_name': 'Test',
            'role': 'client',
          }),
      clientScheduleProvider(_clientId).overrideWith((ref) async => null),
      clientScoreProvider(_clientId).overrideWith((ref) async => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _settle(t);
}

/// Opens a sheet and lets its prefill read answer.
Future<void> _open(WidgetTester t, String label) async {
  final target = find.text(label).last;
  await t.ensureVisible(target);
  await _settle(t);
  await t.tap(target);
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _settle(t);
}

Future<void> _tapText(WidgetTester t, String text) async {
  await t.tap(find.text(text).last);
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _settle(t);
}

/// postgrest-dart retries a GET that failed on the connection, with backoff,
/// before it throws: pump (fake time) and yield (real I/O) until [f] appears.
Future<void> _waitFor(WidgetTester t, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(seconds: 1));
  }
}

Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

ElevatedButton _button(WidgetTester t, String label) => t.widget<ElevatedButton>(
    find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)));

const _lock =
    'Coaching services unlock once this client subscribes to one of your plans.';

void main() {
  final server = _Server();
  final reported = <String>[];

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

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink((f) => reported.add(f.origin));
  });
  tearDown(resetFailureSink);

  group('Set Nutrition Targets', () {
    testWidgets('a failed read (500): notice, Save disabled, no write sent',
        (t) async {
      server.plan = {
        'calories_target': 2100, 'protein_g': 160, 'carbs_g': 200, 'fat_g': 70,
      };
      server.fail['client_nutrition_plans'] = _Mode.http500;
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');

      expect(find.text("Couldn't load the current plan."), findsOneWidget);
      expect(find.textContaining('contact support'), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsNothing,
          reason: 'the server answered; this is not a connection failure');
      expect(find.text('Try again'), findsOneWidget);
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNull,
          reason: 'THE defect: Save wrote a blank form over the plan');

      // The coach types figures anyway and taps Save.
      await t.enterText(_field('1850'), '1200');
      await t.enterText(_field('140'), '50');
      await t.enterText(_field('170'), '50');
      await t.enterText(_field('60'), '20');
      await _tapText(t, 'Save Nutrition Plan');
      expect(server.writes, isEmpty, reason: 'no write from an unloaded form');
      expect(reported, contains('AssignNutritionSheet._loadCurrentPlan'));

      // Try again → the read succeeds, the plan fills the form, Save enables.
      server.fail.clear();
      await _tapText(t, 'Try again');
      expect(find.text("Couldn't load the current plan."), findsNothing);
      expect(find.text('2100'), findsOneWidget);
      expect(find.text('160'), findsOneWidget);
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNotNull);
    });

    testWidgets('a dropped connection says to check the connection', (t) async {
      server.fail['client_nutrition_plans'] = _Mode.network;
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');
      await _waitFor(t, find.text("Couldn't load the current plan."));

      expect(find.text("Couldn't load the current plan."), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNull);
    });

    testWidgets('a loaded "no plan" still saves as today (control)', (t) async {
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');

      expect(find.text("Couldn't load the current plan."), findsNothing);
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNotNull);
      await t.enterText(_field('1850'), '2200');
      await t.enterText(_field('140'), '150');
      await t.enterText(_field('170'), '240');
      await t.enterText(_field('60'), '70');
      await _tapText(t, 'Save Nutrition Plan');

      expect(server.writes.first, 'POST assign_nutrition_plan');
      final body = jsonDecode(server.writes[1].substring(5)) as Map;
      expect(body, containsPair('p_client_id', _clientId));
      expect(body, containsPair('p_calories_target', 2200));
      expect(body, containsPair('p_protein_g', 150));
      expect(body, containsPair('p_carbs_g', 240));
      expect(body, containsPair('p_fat_g', 70));
      expect(find.text('Nutrition plan saved!'), findsOneWidget);
    });
  });

  group('Assign Habits', () {
    testWidgets('a failed read: notice, Assign disabled, habits never switched off',
        (t) async {
      server.habits = [
        {'name': 'Sleep', 'target_value': 7, 'is_active': true},
      ];
      server.fail['client_habits'] = _Mode.http500;
      await _pumpPage(t);
      await _open(t, 'Assign Habits');

      expect(find.text("Couldn't load the current habits."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await t.tap(find.text('Steps'));
      await _settle(t);
      expect(_button(t, 'Assign 1 Habit').onPressed, isNull,
          reason: 'THE defect: Save switched off the unseen Sleep habit');
      await _tapText(t, 'Assign 1 Habit');
      expect(server.writes, isEmpty,
          reason: 'no PATCH is_active=false, no insert');
      expect(reported, contains('AssignHabitsSheet._loadCurrentHabits'));

      // Try again → Sleep is pre-selected alongside Steps, Assign enables.
      server.fail.clear();
      await _tapText(t, 'Try again');
      expect(find.text("Couldn't load the current habits."), findsNothing);
      expect(_button(t, 'Assign 2 Habits').onPressed, isNotNull);
      await _tapText(t, 'Assign 2 Habits');
      expect(server.writes, containsAllInOrder(['PATCH client_habits', 'POST client_habits']));
    });

    testWidgets('a loaded "no habits" still assigns as today (control)',
        (t) async {
      await _pumpPage(t);
      await _open(t, 'Assign Habits');
      expect(find.text("Couldn't load the current habits."), findsNothing);

      await t.tap(find.text('Steps'));
      await _settle(t);
      await _tapText(t, 'Assign 1 Habit');
      expect(server.writes, containsAllInOrder(['PATCH client_habits', 'POST client_habits']));
      expect(find.text('Habits assigned!'), findsOneWidget);
    });
  });

  group('paid-plan check', () {
    testWidgets('a failed check is never shown as "not subscribed"', (t) async {
      server.fail['subscriptions'] = _Mode.http500;
      await _pumpPage(t);

      expect(find.text(_lock), findsNothing,
          reason: 'THE defect: a failed read read as "not subscribed"');
      expect(find.text("Couldn't check this client's plan."), findsOneWidget);
      expect(find.text('Assign / Change Program'), findsNothing);
      expect(reported, contains('CoachProgramService.clientHasPaidPlan'));

      server.fail.clear();
      await t.ensureVisible(find.text('Try again'));
      await _tapText(t, 'Try again');
      expect(find.text("Couldn't check this client's plan."), findsNothing);
      expect(find.text('Assign / Change Program'), findsOneWidget);
    });

    testWidgets('a dropped connection: connection hint, no lock', (t) async {
      server.fail['subscriptions'] = _Mode.network;
      await _pumpPage(t);
      await _waitFor(t, find.text("Couldn't check this client's plan."));
      expect(find.text(_lock), findsNothing);
      expect(find.text("Couldn't check this client's plan."), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsOneWidget);
    });

    testWidgets('a client with no plan still sees the lock (control)',
        (t) async {
      server.subscribed = false;
      await _pumpPage(t);
      expect(find.text(_lock), findsOneWidget);
      expect(find.text("Couldn't check this client's plan."), findsNothing);
      expect(find.text('Assign / Change Program'), findsNothing);
    });
  });
}
