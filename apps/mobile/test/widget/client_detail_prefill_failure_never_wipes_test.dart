import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

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
// Review round (UX/security/QA notes): the inputs and habit toggles are locked
// too until the read succeeds (so a successful Try again never merges into
// blind edits); the notices are live regions with a labelled Try again and a
// distinct repeat-failure title; the Action Center tells "still checking"
// from "couldn't check"; the in-flight retry, the loading text, a failed
// refresh after a success, and each network exception class are pinned.
//
// The REAL CoachProgramService runs against a fake PostgREST (500, a thrown
// network exception, or a held response per table); the fake records every
// write.
//
// HOW TO SEE IT FAIL: check out e8ef987's client_detail_screen.dart and
// coach_program_service.dart — the failed-read tests find no failure notice,
// an enabled Save, and a write sent. The review-round tests fail on 90e307a's
// client_detail_screen.dart (copy, locked inputs, live regions, snackbars).

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

enum _Mode { ok, http500, network, socket, timeout, authRetryable }

/// Reads of the tables under test fail per [fail] (or wait on [hold]);
/// everything else answers. Every non-GET is recorded in [writes] and fails
/// per [failWrite].
class _Server extends http.BaseClient {
  final Map<String, _Mode> fail = {};
  final Map<String, _Mode> failWrite = {};
  final Map<String, Completer<void>> hold = {};
  Map<String, Object?>? plan;
  List<Map<String, Object?>> habits = [];
  bool subscribed = true;
  final List<String> writes = [];

  void reset() {
    fail.clear();
    failWrite.clear();
    for (final h in hold.values) {
      if (!h.isCompleted) h.complete();
    }
    hold.clear();
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
      final failed = _failure(request, failWrite[table] ?? _Mode.ok);
      if (failed != null) return failed;
      return _json(request, request.method == 'POST' ? 201 : 200, []);
    }
    final h = hold[table];
    if (h != null) await h.future;
    final failed = _failure(request, fail[table] ?? _Mode.ok);
    if (failed != null) return failed;
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

  http.StreamedResponse? _failure(http.BaseRequest request, _Mode mode) =>
      switch (mode) {
        _Mode.network =>
          throw http.ClientException('Connection refused', request.url),
        _Mode.socket => throw const SocketException('Network is unreachable'),
        _Mode.timeout => throw TimeoutException('read timed out'),
        _Mode.authRetryable =>
          throw AuthRetryableFetchException(message: 'fetch failed'),
        _Mode.http500 => _json(request, 500,
            {'code': 'XX000', 'message': 'boom', 'details': null, 'hint': null}),
        _Mode.ok => null,
      };

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

/// Lets real I/O (the fake server) answer, then settles the frames.
Future<void> _io(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _settle(t);
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
  await _io(t);
}

/// Opens a sheet and lets its prefill read answer.
Future<void> _open(WidgetTester t, String label) async {
  final target = find.text(label).last;
  await t.ensureVisible(target);
  await _settle(t);
  await t.tap(target);
  await _io(t);
}

Future<void> _tapText(WidgetTester t, String text) async {
  await t.tap(find.text(text).last);
  await _io(t);
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

const _nutritionHints = ['1850', '140', '170', '60', '64'];

List<bool?> _nutritionFieldsEnabled(WidgetTester t) =>
    [for (final h in _nutritionHints) t.widget<TextField>(_field(h)).enabled];

ElevatedButton _button(WidgetTester t, String label) => t.widget<ElevatedButton>(
    find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)));

/// [text] sits inside a `Semantics(liveRegion: true, container: true)`.
bool _inLiveRegion(WidgetTester t, String text) => find
    .ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.liveRegion == true &&
            w.container))
    .evaluate()
    .isNotEmpty;

/// The Approve button on the Action Center row whose text is [rowText].
Finder _approveOn(String rowText) => find.descendant(
    of: find
        .ancestor(of: find.text(rowText), matching: find.byType(Row))
        .first,
    matching: find.text('Approve'));

Finder get _addButton => find.widgetWithText(TextButton, 'Add');

const _lock =
    'Coaching services unlock once this client subscribes to one of your plans.';
const _planFailed = "Couldn't load the current nutrition plan.";
const _planFailedAgain = "Still couldn't load the current nutrition plan.";
const _habitsFailed = "Couldn't load the current habits.";
const _habitsFailedAgain = "Still couldn't load the current habits.";
const _checkFailed = "Couldn't check this client's plan.";
const _checkFailedAgain = "Still couldn't check this client's plan.";
const _checking = "Checking this client's plan…";
const _habitsSheetHint =
    'Tap to assign. For ones with a blank, set the daily target.';

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
    testWidgets(
        'a failed read (500): notice, fields AND Save locked, no write; '
        'a repeat failure says "Still"; a retry that loads unlocks them',
        (t) async {
      server.plan = {
        'calories_target': 2100, 'protein_g': 160, 'carbs_g': 200, 'fat_g': 70,
      };
      server.fail['client_nutrition_plans'] = _Mode.http500;
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');

      expect(find.text(_planFailed), findsOneWidget);
      expect(
          find.textContaining(
              "You can't save until it loads, so this client's plan isn't overwritten."),
          findsOneWidget);
      expect(find.textContaining('If it keeps happening, contact support.'),
          findsOneWidget);
      expect(find.textContaining('Try again. If'), findsNothing,
          reason: 'no "Try again." next step beside a Try again button');
      expect(find.textContaining('Check your connection'), findsNothing,
          reason: 'the server answered; this is not a connection failure');
      expect(find.text('Try again'), findsOneWidget);
      expect(find.bySemanticsLabel('Try again, load current plan'),
          findsOneWidget);
      expect(_inLiveRegion(t, _planFailed), isTrue);
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNull,
          reason: 'THE defect: Save wrote a blank form over the plan');
      expect(_nutritionFieldsEnabled(t), everyElement(isFalse),
          reason: 'N1: no blind edits a later prefill would overwrite');
      await _tapText(t, 'Save Nutrition Plan');
      expect(server.writes, isEmpty, reason: 'no write from an unloaded form');
      expect(reported, contains('AssignNutritionSheet._loadCurrentPlan'));

      // Try again, still failing → the failure is perceptibly repeated.
      await _tapText(t, 'Try again');
      expect(find.text(_planFailedAgain), findsOneWidget);
      expect(find.text(_planFailed), findsNothing);
      expect(_nutritionFieldsEnabled(t), everyElement(isFalse));

      // Try again → the read succeeds, the plan fills the form, all unlock.
      server.fail.clear();
      await _tapText(t, 'Try again');
      expect(find.text(_planFailedAgain), findsNothing);
      expect(find.text('2100'), findsOneWidget);
      expect(find.text('160'), findsOneWidget);
      expect(_nutritionFieldsEnabled(t), everyElement(isTrue));
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNotNull);
    });

    testWidgets('while the read is in flight: "Loading the current plan…", '
        'fields and Save locked', (t) async {
      final gate = server.hold['client_nutrition_plans'] = Completer<void>();
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');

      expect(find.text('Loading the current plan…'), findsOneWidget);
      expect(_inLiveRegion(t, 'Loading the current plan…'), isTrue);
      expect(_button(t, 'Save Nutrition Plan').onPressed, isNull);
      expect(_nutritionFieldsEnabled(t), everyElement(isFalse));

      gate.complete();
      await _io(t);
      expect(find.text('Loading the current plan…'), findsNothing);
      expect(_nutritionFieldsEnabled(t), everyElement(isTrue));
    });

    for (final mode in [
      _Mode.network,
      _Mode.socket,
      _Mode.timeout,
      _Mode.authRetryable,
    ]) {
      testWidgets('a ${mode.name} failure says to check the connection',
          (t) async {
        server.fail['client_nutrition_plans'] = mode;
        await _pumpPage(t);
        await _open(t, 'Set Nutrition Targets');
        await _waitFor(t, find.text(_planFailed));

        expect(find.text(_planFailed), findsOneWidget);
        expect(find.textContaining('Check your connection'), findsOneWidget);
        expect(find.textContaining('contact support'), findsNothing);
        expect(_button(t, 'Save Nutrition Plan').onPressed, isNull);
      });
    }

    testWidgets('a loaded "no plan" still saves as today (control)', (t) async {
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');

      expect(find.text(_planFailed), findsNothing);
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

    Future<void> saveAgainstFailure(WidgetTester t, _Mode mode) async {
      server.failWrite['assign_nutrition_plan'] = mode;
      await _pumpPage(t);
      await _open(t, 'Set Nutrition Targets');
      await t.enterText(_field('1850'), '2200');
      await t.enterText(_field('140'), '150');
      await t.enterText(_field('170'), '240');
      await t.enterText(_field('60'), '70');
      await _tapText(t, 'Save Nutrition Plan');
    }

    testWidgets('a save the server refused (500) is not called a connection '
        'problem', (t) async {
      await saveAgainstFailure(t, _Mode.http500);
      expect(
          find.text("Couldn't save the plan. Try again, and if it keeps "
              'happening, contact support.'),
          findsOneWidget);
      expect(find.text('Nutrition plan saved!'), findsNothing);
    });

    testWidgets('a save that lost the connection says so', (t) async {
      await saveAgainstFailure(t, _Mode.network);
      expect(
          find.text(
              "Couldn't save the plan — check your connection and try again."),
          findsOneWidget);
    });
  });

  group('Assign Habits', () {
    testWidgets(
        'a failed read: notice, toggles AND Assign locked, habits never '
        'switched off; a retry that loads selects only the server habits',
        (t) async {
      server.habits = [
        {'name': 'Sleep', 'target_value': 7, 'is_active': true},
      ];
      server.fail['client_habits'] = _Mode.http500;
      await _pumpPage(t);
      await _open(t, 'Assign Habits');

      expect(find.text(_habitsFailed), findsOneWidget);
      expect(
          find.textContaining("You can't save until they load, so this "
              "client's habits aren't switched off."),
          findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.bySemanticsLabel('Try again, load current habits'),
          findsOneWidget);
      expect(_inLiveRegion(t, _habitsFailed), isTrue);

      // N1: a tap on a habit does nothing while unloaded.
      await t.tap(find.text('Steps'));
      await _settle(t);
      expect(find.text('Assign 0 Habits'), findsOneWidget,
          reason: 'the toggle is locked until the read succeeds');
      expect(_button(t, 'Assign 0 Habits').onPressed, isNull);
      await _tapText(t, 'Assign 0 Habits');
      expect(server.writes, isEmpty,
          reason: 'no PATCH is_active=false, no insert');
      expect(reported, contains('AssignHabitsSheet._loadCurrentHabits'));

      // Try again, still failing → "Still couldn't…".
      await _tapText(t, 'Try again');
      expect(find.text(_habitsFailedAgain), findsOneWidget);

      // Try again → only the server's Sleep is selected (nothing merged in).
      server.fail.clear();
      await _tapText(t, 'Try again');
      expect(find.text(_habitsFailedAgain), findsNothing);
      expect(find.text('Assign 1 Habit'), findsOneWidget);
      await t.tap(find.text('Steps'));
      await _settle(t);
      expect(_button(t, 'Assign 2 Habits').onPressed, isNotNull);
      await _tapText(t, 'Assign 2 Habits');
      expect(server.writes, containsAllInOrder(['PATCH client_habits', 'POST client_habits']));
    });

    testWidgets('while the read is in flight: "Loading the current habits…", '
        'toggles locked', (t) async {
      final gate = server.hold['client_habits'] = Completer<void>();
      await _pumpPage(t);
      await _open(t, 'Assign Habits');

      expect(find.text('Loading the current habits…'), findsOneWidget);
      expect(_inLiveRegion(t, 'Loading the current habits…'), isTrue);
      await t.tap(find.text('Steps'));
      await _settle(t);
      expect(find.text('Assign 0 Habits'), findsOneWidget);

      gate.complete();
      await _io(t);
      expect(find.text('Loading the current habits…'), findsNothing);
      await t.tap(find.text('Steps'));
      await _settle(t);
      expect(find.text('Assign 1 Habit'), findsOneWidget);
    });

    testWidgets('a loaded "no habits" still assigns as today (control)',
        (t) async {
      await _pumpPage(t);
      await _open(t, 'Assign Habits');
      expect(find.text(_habitsFailed), findsNothing);

      await t.tap(find.text('Steps'));
      await _settle(t);
      await _tapText(t, 'Assign 1 Habit');
      expect(server.writes, containsAllInOrder(['PATCH client_habits', 'POST client_habits']));
      expect(find.text('Habits assigned!'), findsOneWidget);
    });

    testWidgets('an assign the server refused (500) is not called a '
        'connection problem', (t) async {
      server.failWrite['client_habits'] = _Mode.http500;
      await _pumpPage(t);
      await _open(t, 'Assign Habits');
      await t.tap(find.text('Steps'));
      await _settle(t);
      await _tapText(t, 'Assign 1 Habit');
      expect(
          find.text("Couldn't assign habits. Try again, and if it keeps "
              'happening, contact support.'),
          findsOneWidget);
      expect(find.text('Habits assigned!'), findsNothing);
    });

    testWidgets('an assign that lost the connection says so', (t) async {
      server.failWrite['client_habits'] = _Mode.network;
      await _pumpPage(t);
      await _open(t, 'Assign Habits');
      await t.tap(find.text('Steps'));
      await _settle(t);
      await _tapText(t, 'Assign 1 Habit');
      expect(
          find.text(
              "Couldn't assign habits — check your connection and try again."),
          findsOneWidget);
    });
  });

  group('paid-plan check', () {
    testWidgets('a failed check is never shown as "not subscribed"', (t) async {
      server.fail['subscriptions'] = _Mode.http500;
      await _pumpPage(t);

      expect(find.text(_lock), findsNothing,
          reason: 'THE defect: a failed read read as "not subscribed"');
      expect(find.text(_checkFailed), findsOneWidget);
      expect(_inLiveRegion(t, _checkFailed), isTrue);
      expect(find.bySemanticsLabel("Try again, check this client's plan"),
          findsOneWidget);
      expect(find.text('Assign / Change Program'), findsNothing);
      expect(reported, contains('CoachProgramService.clientHasPaidPlan'));

      server.fail.clear();
      await t.ensureVisible(find.text('Try again'));
      await _tapText(t, 'Try again');
      expect(find.text(_checkFailed), findsNothing);
      expect(find.text('Assign / Change Program'), findsOneWidget);
    });

    testWidgets(
        'a Try again in flight shows "Checking…" (not the stale failure); '
        'failing again says "Still couldn\'t…"', (t) async {
      server.fail['subscriptions'] = _Mode.http500;
      await _pumpPage(t);
      expect(find.text(_checkFailed), findsOneWidget);

      final gate = server.hold['subscriptions'] = Completer<void>();
      await t.ensureVisible(find.text('Try again'));
      await _tapText(t, 'Try again');
      expect(find.text(_checking), findsOneWidget,
          reason: 'the retry is in flight');
      expect(find.text(_checkFailed), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(_inLiveRegion(t, _checking), isTrue);

      gate.complete();
      await _io(t);
      expect(find.text(_checkFailedAgain), findsOneWidget,
          reason: 'a repeat failure must not look like nothing happened');
      expect(find.text(_lock), findsNothing);
    });

    testWidgets('a check that answered, then a refresh that FAILED, fails '
        'closed (services hidden)', (t) async {
      await _pumpPage(t);
      expect(find.text('Assign / Change Program'), findsOneWidget);

      server.fail['subscriptions'] = _Mode.http500;
      final container = ProviderScope.containerOf(
          t.element(find.byType(ClientDetailScreen)));
      container.invalidate(clientHasPaidPlanProvider(_clientId));
      await _io(t);

      expect(find.text(_checkFailed), findsOneWidget);
      expect(find.text('Assign / Change Program'), findsNothing,
          reason: 'a stale "paid" must not survive a failed refresh');
      expect(_addButton, findsNothing);
    });

    testWidgets('a dropped connection: connection hint, no lock', (t) async {
      server.fail['subscriptions'] = _Mode.network;
      await _pumpPage(t);
      await _waitFor(t, find.text(_checkFailed));
      expect(find.text(_lock), findsNothing);
      expect(find.text(_checkFailed), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsOneWidget);
    });

    testWidgets('a client with no plan still sees the lock (control)',
        (t) async {
      server.subscribed = false;
      await _pumpPage(t);
      expect(find.text(_lock), findsOneWidget);
      expect(find.text(_checkFailed), findsNothing);
      expect(find.text('Assign / Change Program'), findsNothing);
      expect(_addButton, findsNothing);
    });
  });

  group('Action Center while the plan is unconfirmed', () {
    testWidgets('check FAILED: Approve opens nothing and points to Coaching '
        'services; no Add', (t) async {
      server.fail['subscriptions'] = _Mode.http500;
      await _pumpPage(t);
      expect(find.text(_checkFailed), findsOneWidget);
      expect(_addButton, findsNothing);

      await t.ensureVisible(_approveOn('Assign Water Habit'));
      await t.tap(_approveOn('Assign Water Habit'));
      await _io(t);
      expect(
          find.text("Couldn't check this client's plan. "
              'Use Try again in Coaching services.'),
          findsOneWidget);
      expect(find.text(_habitsSheetHint), findsNothing,
          reason: 'an unconfirmed plan must not open the service sheet');
      expect(server.writes, isEmpty);
    });

    testWidgets('check still LOADING: Approve says to wait; no Add',
        (t) async {
      final gate = server.hold['subscriptions'] = Completer<void>();
      await _pumpPage(t);
      expect(find.text(_checking), findsOneWidget);
      expect(_addButton, findsNothing);

      await t.ensureVisible(_approveOn('Assign Water Habit'));
      await t.tap(_approveOn('Assign Water Habit'));
      await _settle(t);
      expect(
          find.text(
              "Still checking this client's plan — try again in a moment."),
          findsOneWidget);
      expect(find.text(_habitsSheetHint), findsNothing);
      gate.complete();
      await _io(t);
    });

    testWidgets('check answered PAID: Add shown, Approve opens the sheet '
        '(control)', (t) async {
      await _pumpPage(t);
      expect(_addButton, findsOneWidget);
      await t.ensureVisible(_approveOn('Assign Water Habit'));
      await t.tap(_approveOn('Assign Water Habit'));
      await _io(t);
      expect(find.text(_habitsSheetHint), findsOneWidget);
    });
  });
}
