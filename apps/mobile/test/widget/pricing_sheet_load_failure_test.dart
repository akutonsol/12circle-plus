import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
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
const _saveNetwork =
    "Couldn't save your price — check your connection and try again.";
const _saveFailed =
    "Couldn't confirm your price was saved — it may still have saved. "
    'Reopen this to check, or try again in a moment. If it keeps happening, '
    'contact support.';
const _signedOut = "You're signed out — sign in again to set your price.";

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
/// Whether [f]'s semantics node, or one it sits in, is a live region.
bool _inLiveRegion(WidgetTester tester, Finder f) {
  SemanticsNode? n = tester.getSemantics(f);
  while (n != null) {
    if (n.getSemanticsData().flagsCollection.isLiveRegion) return true;
    n = n.parent;
  }
  return false;
}

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

/// How the Save (PATCH user_profiles) answers.
enum _Save { ok, serverError, offline }

class _Server extends http.BaseClient {
  _Read answer = _Read.price120;
  _Save saveAnswer = _Save.ok;
  final reads = <String>[];
  final saves = <String>[];

  /// While set, the opening read waits on it (the sheet stays loading).
  Completer<void>? hold;

  /// While set, the read / the save throws this instead of answering — one
  /// per kind of failure to reach the server (SocketException, ...).
  Object Function(http.BaseRequest)? readThrows;
  Object Function(http.BaseRequest)? saveThrows;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path == '/rest/v1/user_profiles') {
      reads.add(request.url.query);
      if (hold != null) await hold!.future;
      if (readThrows != null) throw readThrows!(request);
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
    if (request.method == 'PATCH' &&
        request.url.path == '/rest/v1/user_profiles') {
      saves.add(request.url.query);
      if (saveThrows != null) throw saveThrows!(request);
      switch (saveAnswer) {
        case _Save.ok:
          return _json([
            {'id': _uid}
          ], 200, request);
        case _Save.serverError:
          return _json({'message': 'boom', 'code': 'XX000'}, 500, request);
        case _Save.offline:
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
      ..saveAnswer = _Save.ok
      ..hold = null
      ..readThrows = null
      ..saveThrows = null
      ..reads.clear()
      ..saves.clear();
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

  Future<void> openSheet(WidgetTester tester,
      {Size size = const Size(1000, 2000)}) async {
    tester.view.physicalSize = size;
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
    // S1: the server's own error text is never shown.
    expect(find.textContaining('boom'), findsNothing);
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

  Future<void> tapSave(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '150');
    await tester.tap(find.text('Save price'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  // U2: a Save the server refused is not a connection problem. HOW TO SEE IT
  // FAIL: on af83748 every non-StateError save said "check your connection".
  testWidgets(
      'a server failure on Save gives the try-later step with the may-have-'
      'saved caution — not the connection hint, never the server text',
      (tester) async {
    server.saveAnswer = _Save.serverError;
    await openSheet(tester);
    await tapSave(tester);
    expect(server.saves, isNotEmpty, reason: 'premise: the save was sent');

    expect(_inSheet(_saveFailed), findsOneWidget);
    expect(find.textContaining('check your connection'), findsNothing);
    expect(find.textContaining('boom'), findsNothing,
        reason: "S1: the server's error text never reaches the screen");
    expect(find.text('Save price'), findsOneWidget, reason: 'sheet stays open');
  });

  testWidgets('control: a network failure on Save says check your connection',
      (tester) async {
    server.saveAnswer = _Save.offline;
    await openSheet(tester);
    await tapSave(tester);
    expect(server.saves, isNotEmpty, reason: 'premise: the save was sent');

    expect(_inSheet(_saveNetwork), findsOneWidget);
    expect(find.text(_saveFailed), findsNothing);
  });

  // U4: the opening spinner is announced. HOW TO SEE IT FAIL: on af83748 the
  // indicator has no semantics label.
  testWidgets('the loading spinner is announced as "Loading your price"',
      (tester) async {
    final handle = tester.ensureSemantics();
    server.hold = Completer<void>();
    await openSheet(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'premise: still loading');
    expect(find.bySemanticsLabel('Loading your price'), findsOneWidget);

    server.hold!.complete();
    await settle(tester);
    expect(find.text('Save price'), findsOneWidget);
    handle.dispose();
  });

  // U5: at large text on a short phone the sheet scrolls instead of
  // overflowing. HOW TO SEE IT FAIL: on af83748 the Column overflows.
  testWidgets(
      'no overflow at text scale 2.0 on a 320-wide short screen '
      '(load-failure state)', (tester) async {
    server.answer = _Read.serverError;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openSheet(tester, size: const Size(320, 480));

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(_inSheet(_couldntLoad), findsOneWidget);
    await tester.scrollUntilVisible(_inSheet('Try again'), 100,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    await tester.tap(_inSheet('Try again'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  // M1 (mutation round): Try again goes back to the spinner, so a second tap
  // while the re-read is in flight cannot start a second read, and the empty
  // price form never flashes up in between.
  testWidgets(
      'Try again tapped twice during the re-read starts exactly one read',
      (tester) async {
    server.answer = _Read.serverError;
    await openSheet(tester);
    expect(_inSheet(_couldntLoad), findsOneWidget, reason: 'premise');
    final before = server.reads.length;

    server
      ..answer = _Read.price120
      ..hold = Completer<void>();
    await tester.tap(_inSheet('Try again'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the re-read shows the spinner');
    expect(find.byType(TextField), findsNothing,
        reason: 'the empty price form does not flash up during the re-read');
    expect(_inSheet('Try again'), findsNothing,
        reason: 'no second Try again while the re-read is in flight');
    // A quick second tap: only possible if the button is still there.
    if (_inSheet('Try again').evaluate().isNotEmpty) {
      await tester.tap(_inSheet('Try again'));
      await tester.pump();
    }

    server.hold!.complete();
    await settle(tester);
    expect(server.reads.length, before + 1, reason: 'exactly one re-read');
    expect(_fieldText(tester), '120');
  });

  // M2 (mutation round): every kind of failure to reach the server gets the
  // connection copy, on the opening read and on Save — not only
  // http.ClientException.
  final networkFailures = <String, Object Function(http.BaseRequest)>{
    'SocketException': (r) => const SocketException('Network is unreachable'),
    'TimeoutException': (r) =>
        TimeoutException('read timed out', const Duration(seconds: 10)),
    'http.ClientException': (r) =>
        http.ClientException('Connection refused', r.url),
    'AuthRetryableFetchException': (r) =>
        AuthRetryableFetchException(message: 'fetch failed'),
  };
  for (final entry in networkFailures.entries) {
    testWidgets('a ${entry.key} on the opening read says check your connection',
        (tester) async {
      server.readThrows = entry.value;
      await openSheet(tester);
      // postgrest-dart may retry a GET that throws (1 s + 2 s + 4 s on the
      // fake clock); advance past it.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(server.reads, isNotEmpty, reason: 'premise: the read was made');
      expect(_inSheet(_couldntLoad), findsOneWidget);
      expect(_inSheet(_checkConnection), findsOneWidget,
          reason: '${entry.key} is a failure to reach the server');
      expect(find.text(_tryLater), findsNothing);
      expectNoPriceForm();
    });

    testWidgets('a ${entry.key} on Save says check your connection',
        (tester) async {
      server.saveThrows = entry.value;
      await openSheet(tester);
      await tapSave(tester);
      expect(server.saves, isNotEmpty, reason: 'premise: the save was sent');
      expect(_inSheet(_saveNetwork), findsOneWidget,
          reason: '${entry.key} is a failure to reach the server');
      expect(find.text(_saveFailed), findsNothing);
    });
  }

  // M4 (mutation round): the failure messages that replace the form are live
  // regions, so a screen reader announces them when they appear.
  testWidgets('the load-failure block is announced as a live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    server.answer = _Read.serverError;
    await openSheet(tester);
    expect(_inSheet(_couldntLoad), findsOneWidget, reason: 'premise');
    expect(_inLiveRegion(tester, _inSheet(_couldntLoad)), isTrue);
    expect(_inLiveRegion(tester, _inSheet(_tryLater)), isTrue);
    handle.dispose();
  });

  testWidgets('a failed Save message is announced as a live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    server.saveAnswer = _Save.serverError;
    await openSheet(tester);
    await tapSave(tester);
    expect(_inSheet(_saveFailed), findsOneWidget, reason: 'premise');
    expect(_inLiveRegion(tester, _inSheet(_saveFailed)), isTrue);
    handle.dispose();
  });

  testWidgets('control: the price form is not a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await openSheet(tester);
    expect(_inLiveRegion(tester, find.text('Save price')), isFalse,
        reason: 'the live-region check can say no');
    handle.dispose();
  });

  // Runs last: it signs the shared client out.
  testWidgets('signed out says so instead of an empty field', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    expect(Supabase.instance.client.auth.currentUser, isNull,
        reason: 'premise');
    await openSheet(tester);

    expect(_inSheet(_signedOut), findsOneWidget);
    expectNoPriceForm();
    expect(server.reads, isEmpty, reason: 'nothing to read signed out');
    // M4: announced when it appears.
    expect(_inLiveRegion(tester, _inSheet(_signedOut)), isTrue,
        reason: 'the signed-out message is a live region');
    handle.dispose();
  });
}
