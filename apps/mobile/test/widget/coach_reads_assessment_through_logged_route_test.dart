import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-37 (security ledger F3) — the coach reads a client's assessment
// (PAR-Q / health data) ONLY through the logged route.
//
// The client page read the client's whole `user_profiles` row with
// `select('*')` and rendered PAR-Q answers, risk, medical conditions and
// injuries from it. The protected path, `get_client_assessment(p_client)`
// (migrations 140/141), writes an `assessment_access_log` row before it
// returns and had no app caller, so every coach PHI read went unlogged.
//
// The fake PostgREST below honours `select=`: `*` returns the whole row, a
// column list returns only those columns — so once the page stops asking
// for assessment columns, the RPC is the only place they can come from.
//
// HOW TO SEE IT FAIL: `git checkout 2ecd6e2 -- <coach_ecosystem_provider.dart,
// client_detail_screen.dart>`; no RPC is sent, the profile read is `select=*`,
// and a failed / refused / empty assessment read renders the profile's
// answers (incl. LOW RISK) instead of its own state.

const _uid = '00000000-0000-4000-8000-0000000c0a37';
const _clientId = '00000000-0000-4000-8000-00000000c137';

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

/// The 36 columns `get_client_assessment` returns (migration 141), minus the
/// four that are identity / bookkeeping rather than assessment data. None of
/// these may be asked of `user_profiles` by the client page.
const _assessmentColumns = {
  'date_of_birth', 'gender', 'height_cm', 'weight_kg', 'weight_goal_kg',
  'parq_answers', 'risk_level', 'risk_score', 'risk_flags',
  'medical_conditions', 'has_injuries', 'injury_locations',
  'injury_description', 'food_allergies', 'dietary_restrictions',
  'experience_level', 'worked_with_coach_before', 'activity_level',
  'training_days_per_week', 'training_location', 'sleep_hours',
  'stress_level', 'occupation', 'fitness_goal', 'target_timeline',
  'nutrition_goal', 'protein_confidence', 'biggest_challenges', 'activities',
  'consent_agreed', 'consent_date', 'has_assessment',
};

/// The client's row as the database holds it. LOW risk, no flags — so a page
/// that falls back to it after a failed assessment read shows "low risk".
Map<String, Object?> _dbRow() => {
      'id': _clientId,
      'first_name': 'Jordan',
      'last_name': 'Test',
      'avatar_url': null,
      'coaching_mode': 'coached',
      'created_at': '2026-01-02T10:00:00Z',
      'onboarding_complete': true,
      'role': 'client',
      'risk_level': 'low',
      'risk_score': 0,
      'risk_flags': '',
      'parq_answers': {'1': false, '2': false},
      'medical_conditions': '',
      'has_injuries': false,
      'fitness_goal': 'build_muscle',
      'experience_level': 'beginner',
    };

/// What the RPC answers when it answers with a row: HIGH risk with flags.
Map<String, Object?> _rpcRow({bool hasAssessment = true}) => {
      'client_id': _clientId,
      'has_assessment': hasAssessment,
      'onboarding_complete': hasAssessment,
      'first_name': 'Jordan',
      'last_name': 'Test',
      if (hasAssessment) ...{
        'risk_level': 'high',
        'risk_score': 5,
        'risk_flags': 'heart_condition,chest_pain',
        'parq_answers': {'1': true, '2': true, '3': false},
        'medical_conditions': 'Hypertension',
        'has_injuries': true,
        'injury_locations': 'Left knee',
        'injury_description': 'ACL repair 2024',
        'fitness_goal': 'lose_fat',
        'experience_level': 'beginner',
        'sleep_hours': '6-7',
        'stress_level': 7,
      },
    };

enum _Rpc { row, notCompleted, empty, denied, http500, network }

class _Server extends http.BaseClient {
  _Rpc rpc = _Rpc.row;
  Completer<void>? holdRpc;
  final List<String> rpcBodies = [];
  final List<Uri> profileReads = [];

  void reset() {
    rpc = _Rpc.row;
    holdRpc = null;
    rpcBodies.clear();
    profileReads.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.startsWith('/storage/')) {
      return _json(request, 400,
          {'statusCode': '404', 'error': 'not_found', 'message': 'Object not found'});
    }
    if (path.endsWith('/rpc/get_client_assessment')) {
      rpcBodies.add(request is http.Request ? request.body : '');
      final h = holdRpc;
      if (h != null) await h.future;
      switch (rpc) {
        case _Rpc.row:
          return _json(request, 200, [_rpcRow()]);
        case _Rpc.notCompleted:
          return _json(request, 200, [_rpcRow(hasAssessment: false)]);
        case _Rpc.empty:
          return _json(request, 200, []);
        case _Rpc.denied:
          return _json(request, 403, {
            'code': '42501',
            'message': 'not authorized to read this assessment',
            'details': null,
            'hint': null,
          });
        case _Rpc.http500:
          return _json(request, 500,
              {'code': 'XX000', 'message': 'boom', 'details': null, 'hint': null});
        case _Rpc.network:
          throw http.ClientException('Connection refused', request.url);
      }
    }
    if (request.method != 'GET') return _json(request, 201, []);
    final table = path.split('/').last;
    final wantsObject =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    Object? row;
    if (table == 'user_profiles') {
      profileReads.add(request.url);
      final select = request.url.queryParameters['select'] ?? '*';
      final full = _dbRow();
      row = select == '*'
          ? full
          : {
              for (final c in select.split(',').map((c) => c.trim()))
                if (full.containsKey(c)) c: full[c],
            };
    }
    if (wantsObject) {
      if (row == null) {
        return _json(request, 406, {
          'code': 'PGRST116',
          'message': 'JSON object requested, multiple (or no) rows returned',
          'details': 'The result contains 0 rows',
          'hint': null,
        });
      }
      return _json(request, 200, row);
    }
    return _json(request, 200, [if (row != null) row]);
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

/// Lets real I/O (the fake server) answer, then settles the frames.
Future<void> _io(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(t);
  }
}

Future<void> _pumpPage(WidgetTester t,
    {double width = 1200,
    double height = 4000,
    double textScale = 1,
    bool paid = false}) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, height);
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(ProviderScope(
    overrides: [
      // Only reads unrelated to the assessment are substituted; the page's
      // profile read and assessment read are REAL, against the fake server.
      clientHasPaidPlanProvider(_clientId).overrideWith((ref) async => paid),
      clientScheduleProvider(_clientId).overrideWith((ref) async => null),
      clientScoreProvider(_clientId).overrideWith((ref) async => null),
      myProgramsProvider
          .overrideWith((ref) async => const <Map<String, dynamic>>[]),
    ],
    child: const MaterialApp(
      home: ClientDetailScreen(clientId: _clientId, clientName: 'Jordan'),
    ),
  ));
  await _io(t);
}

Future<void> _openTab(WidgetTester t, String label) async {
  await t.tap(find.widgetWithText(Tab, label));
  await _settle(t);
}

/// Everything rendered as text, lower-cased, across the tab on screen.
String _screenText(WidgetTester t) => find
    .byType(Text)
    .evaluate()
    .map((e) => ((e.widget as Text).data ?? '').toLowerCase())
    .join(' | ');

final _lowRisk = RegExp(r'low\s*risk', caseSensitive: false);

const _noRowCopy = 'No assessment on file for this client yet — it appears '
    'here once they complete one.';
const _notActiveCopy =
    "This client's assessment is available once coaching is active.";
const _riskActionsGap = 'Assessment not loaded — risk actions unavailable';
const _unknownSemantics = 'Risk level unknown — assessment could not load';
const _hiddenSemantics = 'Risk level hidden until coaching is active';

/// [text] sits inside a `Semantics(liveRegion: true, container: true)`.
bool _inLiveRegion(WidgetTester t, Finder text) => find
    .ancestor(
        of: text,
        matching: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.liveRegion == true && w.container))
    .evaluate()
    .isNotEmpty;

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

  testWidgets(
      'the assessment is read through get_client_assessment with p_client, '
      'ONCE per page open — not again on tab switches or rebuilds', (t) async {
    await _pumpPage(t);
    await _openTab(t, 'Assessment');
    await _openTab(t, 'PAR-Q');
    await _openTab(t, 'Overview');
    await _io(t);
    expect(server.rpcBodies, hasLength(1),
        reason: 'the logged RPC is the only assessment read, and it is sent once');
    expect(jsonDecode(server.rpcBodies.single), {'p_client': _clientId});
  });

  testWidgets(
      'the profile read names its columns, and none of them is assessment data',
      (t) async {
    await _pumpPage(t);
    expect(server.profileReads, isNotEmpty, reason: 'the page reads the profile');
    for (final uri in server.profileReads) {
      final select = uri.queryParameters['select'] ?? '*';
      expect(select, isNot('*'),
          reason: 'select=* hands the client\'s whole PAR-Q / health row '
              'to the coach without a log row');
      final cols = select.split(',').map((c) => c.trim()).toSet();
      expect(cols.intersection(_assessmentColumns), isEmpty,
          reason: 'assessment columns must come only from the logged RPC: $select');
    }
  });

  testWidgets('risk, PAR-Q flags, medical and injuries render from the RPC row',
      (t) async {
    await _pumpPage(t);
    expect(server.rpcBodies, hasLength(1), reason: 'the RPC is the source');
    expect(find.text('HIGH RISK'), findsOneWidget, reason: 'overview badge');
    expect(find.textContaining(_lowRisk), findsNothing);

    await _openTab(t, 'PAR-Q');
    expect(find.text('HIGH RISK'), findsOneWidget);
    expect(find.text('Risk Score: 5 / 8'), findsOneWidget);
    expect(find.text('heart condition'), findsOneWidget);
    expect(find.text('chest pain'), findsOneWidget);
    expect(find.text('Heart condition diagnosed by a doctor?'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
    expect(find.text('Hypertension'), findsOneWidget);
    expect(find.text('Left knee'), findsOneWidget);

    await _openTab(t, 'Assessment');
    expect(find.text('6-7'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);
  });

  testWidgets(
      '42501 (not the active coach): "available once coaching is active" — '
      'not empty answers, not "no assessment", not low risk', (t) async {
    server.rpc = _Rpc.denied;
    await _pumpPage(t);
    const msg = "This client's assessment is available once coaching is active.";
    expect(find.text(msg), findsOneWidget, reason: 'overview');
    expect(find.textContaining(_lowRisk), findsNothing);
    expect(find.text('NOT ASSESSED'), findsNothing,
        reason: 'a refused read is not a client who was never assessed');
    for (final tab in ['Assessment', 'PAR-Q']) {
      await _openTab(t, tab);
      expect(find.text(msg), findsOneWidget, reason: tab);
      final text = _screenText(t);
      for (final wrong in ['no assessment on file', 'not completed yet',
          'none reported', 'no injuries reported', 'low risk', 'not assessed']) {
        expect(text.contains(wrong), isFalse, reason: '$tab shows "$wrong"');
      }
      expect(find.textContaining("Couldn't"), findsNothing,
          reason: 'a refusal is an answer, not an outage');
    }
  });

  testWidgets('no row: "No assessment on file", naming the cause (UX-1)',
      (t) async {
    server.rpc = _Rpc.empty;
    await _pumpPage(t);
    expect(find.text(_noRowCopy), findsOneWidget);
    expect(find.textContaining(_lowRisk), findsNothing);
    expect(find.textContaining('Not completed yet'), findsNothing,
        reason: 'no row and has_assessment=false must not read the same');
    expect(find.text(_riskActionsGap), findsNothing,
        reason: 'no assessment is an answer, not a failed read');
    await _openTab(t, 'PAR-Q');
    expect(find.text(_noRowCopy), findsOneWidget);
    final text = _screenText(t);
    expect(text.contains('none reported'), isFalse);
    expect(text.contains('no injuries reported'), isFalse);
  });

  testWidgets(
      'has_assessment = false: "Not completed yet", not "None reported"',
      (t) async {
    server.rpc = _Rpc.notCompleted;
    await _pumpPage(t);
    await _openTab(t, 'PAR-Q');
    expect(find.textContaining('Not completed yet'), findsOneWidget);
    final text = _screenText(t);
    expect(text.contains('none reported'), isFalse,
        reason: 'an intake never filled in has no medical answer to report');
    expect(text.contains('no injuries reported'), isFalse);
    expect(text.contains('low risk'), isFalse);
  });

  testWidgets(
      'a FAILED assessment read (500) is never low risk: it says so, records '
      'it, and the rest of the page keeps working', (t) async {
    server.rpc = _Rpc.http500;
    await _pumpPage(t);
    const failed = "Couldn't load this client's assessment.";
    expect(find.text(failed), findsOneWidget);
    expect(_inLiveRegion(t, find.text(failed)), isTrue);
    expect(find.textContaining('If it keeps happening, contact support.'),
        findsOneWidget);
    expect(find.textContaining('connection'), findsNothing,
        reason: 'a server answer is not a connection problem');
    expect(find.text('RISK UNKNOWN'), findsOneWidget);
    expect(find.textContaining(_lowRisk), findsNothing,
        reason: 'the database row says low — a failed read must not');
    expect(find.text('NOT ASSESSED'), findsNothing);
    expect(find.textContaining('boom'), findsNothing, reason: 'no raw error');
    // The rest of the page still loaded.
    expect(find.text('Jordan Test'), findsOneWidget);
    expect(find.text('Assigned Program'), findsOneWidget);
    expect(reported, contains('clientAssessmentProvider'));

    for (final tab in ['Assessment', 'PAR-Q']) {
      await _openTab(t, tab);
      expect(find.text(failed), findsOneWidget, reason: tab);
      final text = _screenText(t);
      for (final wrong in ['low risk', 'not completed yet', 'none reported',
          'no injuries reported', 'not assessed']) {
        expect(text.contains(wrong), isFalse, reason: '$tab shows "$wrong"');
      }
    }
  });

  testWidgets(
      'a network failure says check your connection; Try again is busy-aware '
      'and a retry that answers renders the assessment', (t) async {
    server.rpc = _Rpc.network;
    await _pumpPage(t);
    await _openTab(t, 'PAR-Q');
    expect(find.text("Couldn't load this client's assessment."), findsOneWidget);
    expect(find.textContaining('Check your connection, then try again.'),
        findsOneWidget);
    expect(find.textContaining(_lowRisk), findsNothing);
    final sentBefore = server.rpcBodies.length;

    final retry = find.widgetWithText(TextButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(t.getSize(retry).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel("Try again, load this client's assessment"),
        findsOneWidget);

    server
      ..rpc = _Rpc.row
      ..holdRpc = Completer<void>();
    await t.tap(retry);
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    // In flight: no second button to fire a second read.
    expect(find.text("Loading this client's assessment…"), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Try again'), findsNothing);
    expect(server.rpcBodies.length, sentBefore + 1);

    server.holdRpc!.complete();
    await _io(t);
    expect(server.rpcBodies.length, sentBefore + 1);
    expect(find.text('Risk Score: 5 / 8'), findsOneWidget);
    expect(find.text('HIGH RISK'), findsOneWidget);
  });

  // ── Review round (UX-1/2/3, SEC S-4) ──────────────────────────

  testWidgets(
      'UX-1: the 42501 panel carries a lock, not the same icon as the '
      'no-row / not-completed panels', (t) async {
    server.rpc = _Rpc.denied;
    await _pumpPage(t);
    final panel = find.ancestor(
        of: find.text(_notActiveCopy), matching: find.byType(Row)).first;
    expect(find.descendant(of: panel, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget);
    expect(
        find.descendant(
            of: panel, matching: find.byIcon(Icons.assignment_outlined)),
        findsNothing);
  });

  testWidgets(
      'UX-2: a refused read shows a "RISK HIDDEN" badge, told to a screen '
      'reader — the header slot is not silently empty', (t) async {
    final handle = t.ensureSemantics();
    server.rpc = _Rpc.denied;
    await _pumpPage(t);
    expect(find.text('RISK HIDDEN'), findsOneWidget);
    expect(find.bySemanticsLabel(_hiddenSemantics), findsOneWidget);
    expect(find.text('NOT ASSESSED'), findsNothing);
    expect(find.text('RISK UNKNOWN'), findsNothing,
        reason: 'a refusal is an answer, not a failed read');
    handle.dispose();
  });

  testWidgets(
      'UX-3: RISK UNKNOWN has its own semantics label and does not look like '
      'NOT ASSESSED', (t) async {
    final handle = t.ensureSemantics();
    server.rpc = _Rpc.http500;
    await _pumpPage(t);
    expect(find.text('RISK UNKNOWN'), findsOneWidget);
    expect(find.bySemanticsLabel(_unknownSemantics), findsOneWidget);
    final label = t.widget<Text>(find.text('RISK UNKNOWN'));
    // NOT ASSESSED is drawn in the muted text colour; UNKNOWN must not be.
    expect(label.style?.color, isNot(const Color(0xFFCFC2D6)));
    expect(find.text('RISK HIDDEN'), findsNothing);
    handle.dispose();
  });

  /// Pumps the page with every FlutterError — overflow reports included —
  /// collected (first line of each) rather than aborting at the first, so a
  /// failing expectation lists every overflow on the page.
  Future<List<String>> pumpCollectingErrors(WidgetTester t,
      {required double width, double textScale = 1, bool paid = false}) async {
    // Tall enough that the ListView builds EVERY card at 2x (at 4000 the
    // Coaching services rows were never built, so their overflow went unseen).
    final height = textScale > 1 ? 16000.0 : 4000.0;
    final previous = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) =>
        errors.add(d.exceptionAsString().split('\n').first);
    try {
      await _pumpPage(t,
          width: width, height: height, textScale: textScale, paid: paid);
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  for (final state in [_Rpc.http500, _Rpc.denied]) {
    testWidgets(
        'UX-3: at 2x text on a 320dp screen the ${state.name} badge neither '
        'overflows nor squeezes the name column — and (P0-FL-48) nothing '
        'else on the page overflows either', (t) async {
      // P0-FL-37 tolerated overflow reports from the score ring and the
      // Action Center here; P0-FL-48 fixed those, so NONE is tolerated now.
      server.rpc = state;
      final errors = await pumpCollectingErrors(t, width: 320, textScale: 2);
      expect(errors, isEmpty,
          reason: 'P0-FL-48: no overflow anywhere at 2x on 320dp');

      final badge = state == _Rpc.http500 ? 'RISK UNKNOWN' : 'RISK HIDDEN';
      expect(find.text(badge), findsOneWidget);
      final header = find
          .ancestor(of: find.text('Jordan Test'), matching: find.byType(Row))
          .first;
      final badgeBox = find
          .ancestor(of: find.text(badge), matching: find.byType(Container))
          .first;
      expect(find.descendant(of: header, matching: badgeBox), findsOneWidget,
          reason: 'the badge sits in the header row');
      final row = t.getRect(header);
      final b = t.getRect(badgeBox);
      expect(b.right, lessThanOrEqualTo(row.right + 0.01),
          reason: 'the header row overflows: badge ends at ${b.right}, '
              'row at ${row.right}');
      // The name's column (the Expanded beside the avatar), not the text run.
      final name = t.getSize(find
          .ancestor(of: find.text('Jordan Test'), matching: find.byType(Column))
          .first);
      expect(name.width, greaterThanOrEqualTo(b.width),
          reason: 'the client name keeps at least as much room as the badge '
              '(name ${name.width}, badge ${b.width})');
    });
  }

  // ── P0-FL-48: 2x text on 320dp, with every Overview card populated ──────

  for (final paid in [false, true]) {
    testWidgets(
        'P0-FL-48: a loaded assessment (Action Center items present, '
        '${paid ? "paid plan: Add shown" : "no paid plan"}) lays out at 2x '
        'text on 320dp with NO overflow', (t) async {
      final errors =
          await pumpCollectingErrors(t, width: 320, textScale: 2, paid: paid);
      expect(find.text('Review High-Risk PAR-Q'), findsOneWidget,
          reason: 'premise: Action Center items are on the page');
      expect(find.text('AI Client Summary'), findsOneWidget);
      expect(find.text('Coach Action Center'), findsOneWidget);
      expect(find.text('Add'), paid ? findsOneWidget : findsNothing);
      expect(find.text('Assigned Program'), findsOneWidget,
          reason: 'premise: the cards below the Action Center were built');
      expect(find.text('Private Notes'), findsOneWidget,
          reason: 'premise: the last action rows were built');
      if (paid) {
        expect(find.text('Assign / Change Program'), findsOneWidget,
            reason: 'premise: the paid Coaching services rows were built');
      }
      expect(errors, isEmpty,
          reason: 'P0-FL-48: the score ring, the AI Client Summary header, '
              'the Action Center header and each Action Center row must fit '
              'at 2x text on a 320dp phone');

      // Content is unchanged: every item still shows its whole text and all
      // three actions.
      for (final item in ['Review High-Risk PAR-Q', 'Review Injury Details']) {
        final text = t.widget<Text>(find.text(item));
        expect(text.overflow, isNot(TextOverflow.ellipsis),
            reason: '"$item" must wrap, not be cut off');
      }
      final rows = find.text('Edit').evaluate().length;
      expect(rows, greaterThanOrEqualTo(2));
      expect(find.text('Approve'), findsNWidgets(rows));
      expect(find.text('Dismiss'), findsNWidgets(rows));
    });
  }

  testWidgets(
      'P0-FL-48: the score ring readout stays inside the ring at 2x text',
      (t) async {
    final errors = await pumpCollectingErrors(t, width: 320, textScale: 2);
    expect(errors, isEmpty);
    final ring = find
        .ancestor(
            of: find.text('/100'),
            matching: find.byWidgetPredicate((w) =>
                w is SizedBox && w.width != null && w.width == w.height))
        .first;
    final box = t.getRect(ring);
    final readout = find.ancestor(
        of: find.text('/100'), matching: find.byType(Column)).first;
    final r = t.getRect(readout);
    expect(
        r.left >= box.left - 0.01 &&
            r.top >= box.top - 0.01 &&
            r.right <= box.right + 0.01 &&
            r.bottom <= box.bottom + 0.01,
        isTrue,
        reason: 'readout $r spills out of the ring $box');
  });

  testWidgets(
      'P0-FL-48: Action Center controls are >= 44px and name the item they act '
      'on for a screen reader', (t) async {
    final handle = t.ensureSemantics();
    await _pumpPage(t, width: 360, paid: true);
    const item = 'Review High-Risk PAR-Q';
    // The item's own card: the nearest decorated Container around its text.
    final row = find
        .ancestor(
            of: find.text(item),
            matching: find.byWidgetPredicate(
                (w) => w is Container && w.decoration != null))
        .first;
    for (final action in ['Approve', 'Edit', 'Dismiss']) {
      final btn = find.descendant(
          of: row, matching: find.widgetWithText(TextButton, action));
      expect(btn, findsOneWidget, reason: '$action sits in the item card');
      expect(find.bySemanticsLabel('$action: $item'), findsOneWidget,
          reason: 'every row has its own Approve / Edit / Dismiss: without '
              'the item they act on a screen reader cannot tell them apart');
      final size = t.getSize(btn);
      expect(size.height, greaterThanOrEqualTo(44), reason: '$action height');
      expect(size.width, greaterThanOrEqualTo(44), reason: '$action width');
    }
    final add = find.widgetWithText(TextButton, 'Add');
    expect(t.getSize(add).height, greaterThanOrEqualTo(44));
    expect(t.getSize(add).width, greaterThanOrEqualTo(44));
    handle.dispose();
  });

  testWidgets(
      'P0-FL-48 N1: the Action Center Add button has a screen-reader name that '
      'starts with its visible text and says what it adds', (t) async {
    final handle = t.ensureSemantics();
    await _pumpPage(t, width: 360, paid: true);
    expect(find.text('Add'), findsOneWidget,
        reason: 'the visible copy is unchanged');
    final add = find.bySemanticsLabel('Add action item');
    expect(add, findsOneWidget,
        reason: 'a bare "Add" does not say what is added');
    final node = t.getSemantics(add);
    expect(node.label, startsWith('Add'),
        reason: 'voice control matches the name by its visible text');
    expect(node, containsSemantics(isButton: true, hasTapAction: true));
    expect(find.bySemanticsLabel('Add'), findsNothing,
        reason: 'one node, not a second bare "Add" beside it');
    handle.dispose();
  });

  testWidgets(
      'P0-FL-48 1x pin: the score ring is still exactly 72dp at 1x text',
      (t) async {
    final errors = await pumpCollectingErrors(t, width: 360);
    expect(errors, isEmpty);
    final ring = find
        .ancestor(
            of: find.text('/100'),
            matching: find.byWidgetPredicate((w) =>
                w is SizedBox && w.width != null && w.width == w.height))
        .first;
    expect(t.getSize(ring), const Size(72, 72),
        reason: 'the 2x fix must not change the 1x ring');
  });

  testWidgets(
      'UX re-check: on a 360dp phone a short badge leaves the name column at '
      'least 60% of the row\'s free width — the badge takes no flex share',
      (t) async {
    final errors = await pumpCollectingErrors(t, width: 360);
    expect(errors, isEmpty, reason: 'P0-FL-48: no overflow is tolerated');

    expect(find.text('HIGH RISK'), findsOneWidget);
    final header = find
        .ancestor(of: find.text('Jordan Test'), matching: find.byType(Row))
        .first;
    final row = t.getRect(header);
    final avatar = t.getRect(
        find.descendant(of: header, matching: find.byType(CircleAvatar)));
    final nameCol = t.getRect(find
        .ancestor(of: find.text('Jordan Test'), matching: find.byType(Column))
        .first);
    // Free width = what the name column and the badge share: the row to the
    // right of the avatar and its gap.
    final free = row.right - nameCol.left;
    expect(nameCol.left, greaterThan(avatar.right),
        reason: 'the name column sits right of the avatar');
    // (The test font draws square glyphs, so HIGH RISK renders ~103dp wide
    // here; with a 1:1 flex split the name column got ~52% of the room.)
    expect(nameCol.width, greaterThanOrEqualTo(free * 0.6 - 0.01),
        reason: 'name column ${nameCol.width} of free width $free '
            '(${(nameCol.width / free * 100).toStringAsFixed(0)}%)');
  });

  for (final state in [_Rpc.http500, _Rpc.network, _Rpc.denied]) {
    testWidgets(
        'SEC S-4:a ${state.name} assessment read says in the Action Center '
        'that risk actions are unavailable', (t) async {
      server.rpc = state;
      await _pumpPage(t);
      expect(find.text(_riskActionsGap), findsOneWidget);
      expect(find.text('Review High-Risk PAR-Q'), findsNothing,
          reason: 'no action is invented from data that did not load');
      expect(find.text('Review Injury Details'), findsNothing);
    });
  }

  testWidgets(
      'SEC S-4: a loaded assessment shows its risk actions and no gap line; '
      'nor is the gap line shown while the read is in flight', (t) async {
    server.holdRpc = Completer<void>();
    await _pumpPage(t);
    expect(find.text("Loading this client's assessment…"), findsOneWidget);
    expect(find.text(_riskActionsGap), findsNothing, reason: 'still loading');
    server.holdRpc!.complete();
    await _io(t);
    expect(find.text('Review High-Risk PAR-Q'), findsOneWidget);
    expect(find.text('Review Injury Details'), findsOneWidget);
    expect(find.text(_riskActionsGap), findsNothing);
  });
}
