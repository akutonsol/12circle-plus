import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-6 (A): the Coaching Price sheet's opening read of the coach's current
// price swallowed every failure (`catch (_) { // Ignore }`) and showed an EMPTY
// price field — the same screen as "no price set". The coach could then type
// and save a price believing none existed. Signed out it was silently empty too.
//
// HOW TO SEE IT FAIL: on 4d1d992 the failed-read tests find the empty field and
// "Save price", and no "Couldn't load your current price".

const _uid = '00000000-0000-4000-8000-0000000b1ce6';
const _couldntLoad = "Couldn't load your current price";
const _checkConnection = 'Check your connection and try again.';
const _tryLater =
    'Try again in a moment. If it keeps happening, contact support.';
const _signedOut = "You're signed out — sign in again to set your price.";

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

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

/// How the opening read of user_profiles.pricing_monthly answers.
enum _Read { price120, noPrice, serverError, offline }

class _Server extends http.BaseClient {
  _Read answer = _Read.price120;
  final reads = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path == '/rest/v1/user_profiles') {
      reads.add(request.url.query);
      switch (answer) {
        case _Read.price120:
          return _json({'pricing_monthly': 120}, 200, request);
        case _Read.noPrice:
          return _json({'pricing_monthly': null}, 200, request);
        case _Read.serverError:
          return _json({'message': 'boom', 'code': 'XX000'}, 500, request);
        case _Read.offline:
          throw http.ClientException('Connection refused', request.url);
      }
    }
    // Sign-out and anything else: an empty success.
    return _json({}, 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
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
    server
      ..answer = _Read.price120
      ..reads.clear();
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

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => showCoachPricingSheet(context),
              child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  void expectNoPriceForm() {
    expect(find.byType(TextField), findsNothing,
        reason: 'THE defect: an empty price field reads as "no price set"');
    expect(find.text('Save price'), findsNothing,
        reason: 'saving over a price the coach could not see is not offered');
  }

  testWidgets(
      'a server failure says it could not load the price, with the '
      'non-network next step and Try again — no empty field', (tester) async {
    server.answer = _Read.serverError;
    await openSheet(tester);
    expect(server.reads, isNotEmpty, reason: 'premise: the read was made');

    expect(_inSheet(_couldntLoad), findsOneWidget);
    expect(_inSheet(_tryLater), findsOneWidget,
        reason: 'a server answer is not a connection problem');
    expect(find.text(_checkConnection), findsNothing);
    expect(_inSheet('Try again'), findsOneWidget);
    expectNoPriceForm();
    expect(reported.map((f) => f.origin), contains('CoachPricingSheet._load'),
        reason: 'the failure is recorded, not swallowed');
  });

  testWidgets('a network failure says check your connection', (tester) async {
    server.answer = _Read.offline;
    await openSheet(tester);
    // postgrest-dart 2.7 retries a GET that throws 3 times, 1 s + 2 s + 4 s
    // apart, before the error reaches the sheet. Those delays run on the
    // test's fake clock, so advance it past them.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(server.reads, hasLength(4), reason: 'premise: retries exhausted');

    expect(_inSheet(_couldntLoad), findsOneWidget);
    expect(_inSheet(_checkConnection), findsOneWidget);
    expect(find.text(_tryLater), findsNothing);
    expectNoPriceForm();
  });

  testWidgets('Try again re-reads and, on success, shows the saved price',
      (tester) async {
    server.answer = _Read.serverError;
    await openSheet(tester);
    expect(_inSheet(_couldntLoad), findsOneWidget, reason: 'premise');
    final before = server.reads.length;

    server.answer = _Read.price120;
    await tester.tap(_inSheet('Try again'));
    await settle(tester);

    expect(server.reads.length, before + 1, reason: 'Try again re-ran _load');
    expect(find.text(_couldntLoad), findsNothing);
    expect(_fieldText(tester), '120');
    expect(find.text('Save price'), findsOneWidget);
  });

  testWidgets('control: a saved price is shown in the field', (tester) async {
    await openSheet(tester);
    expect(_fieldText(tester), '120');
    expect(find.text('Save price'), findsOneWidget);
    expect(find.text(_couldntLoad), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets('control: a successful read of no price shows the empty field',
      (tester) async {
    server.answer = _Read.noPrice;
    await openSheet(tester);
    expect(_fieldText(tester), '');
    expect(find.text('Save price'), findsOneWidget);
    expect(find.text(_couldntLoad), findsNothing);
    expect(reported, isEmpty);
  });

  // Runs last: it signs the shared client out.
  testWidgets('signed out says so instead of an empty field', (tester) async {
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    expect(Supabase.instance.client.auth.currentUser, isNull,
        reason: 'premise');
    await openSheet(tester);

    expect(_inSheet(_signedOut), findsOneWidget);
    expectNoPriceForm();
    expect(server.reads, isEmpty, reason: 'nothing to read signed out');
  });
}
