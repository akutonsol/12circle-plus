import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-3: the coach's two price screens said a price was saved whatever
// happened.
//
//   * Coaching Price sheet (`_save`): no try/catch. A 0-row update said
//     "Pricing updated. Clients will see your new rate."; a thrown write left
//     the button spinning forever with nothing said.
//   * Client profile -> Set Custom Price: a 0-row update (no relationship with
//     this client, RLS refusal) said "Custom price set to $X/mo." while
//     create-checkout kept charging the standard rate.
//
// HOW TO SEE IT FAIL: on a39435d (PR #172) the 0-row cases show the success
// copy, and the failed-write case leaves the spinner up.
//
// UX follow-up (U1-U5): every failure message must be shown INSIDE the sheet
// or dialog. On e239eed they were SnackBars on the page's messenger, under the
// modal bottom sheet / dialog scrim, so the coach saw only the spinner stop.
// The assertions below are scoped with find.descendant of the BottomSheet /
// AlertDialog, so a SnackBar under the modal does not satisfy them.

const _uid = '00000000-0000-4000-8000-0000000b1ce2';
const _sheetSaved = 'Pricing updated. Clients will see your new rate.';
const _generic =
    "Couldn't save your price — check your connection and try again.";
const _sheetZeroRows =
    "Your price couldn't be saved. Nothing was changed — try again.";
const _sheetInvalid = r'Enter a monthly price above $0.';
const _dialogSaved = r'Custom price set to $150/mo.';
const _dialogNoRelationship =
    'No coaching relationship with this client — nothing was changed.';
const _dialogParseError = 'Enter the monthly price as a number, like 150.';

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
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

enum _Patch { oneRow, zeroRows, fails }

class _Server extends http.BaseClient {
  _Patch mode = _Patch.oneRow;
  final calls = <String>[];

  /// When set, a PATCH waits for it before answering (in-flight tests).
  Completer<void>? gate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add('${request.method} ${request.url.path}');
    if (request.method == 'PATCH') {
      if (gate != null) await gate!.future;
      return switch (mode) {
        _Patch.oneRow => _json([
            {'id': 'row-1'}
          ], 200, request),
        _Patch.zeroRows => _json([], 200, request),
        _Patch.fails => _json({'message': 'offline'}, 500, request),
      };
    }
    // The sheet's opening read of the current price (maybeSingle).
    if (request.headers['Accept']?.contains('vnd.pgrst.object') ?? false) {
      return _json({'pricing_monthly': 120}, 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;

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
      ..mode = _Patch.oneRow
      ..gate = null
      ..calls.clear();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens [open] from a button in a plain app.
  Future<void> host(
      WidgetTester tester, void Function(BuildContext) open) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => open(context), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  group('Coaching Price sheet', () {
    Future<void> saveSheet(WidgetTester tester, {String price = '150'}) async {
      await host(tester, showCoachPricingSheet);
      expect(find.text('Save price'), findsOneWidget, reason: 'premise');
      await tester.enterText(find.byType(TextField), price);
      await tester.tap(find.text('Save price'));
      await settle(tester);
    }

    testWidgets(
        'a 0-row save says nothing changed INSIDE the sheet, not '
        '"Pricing updated."', (tester) async {
      server.mode = _Patch.zeroRows;
      await saveSheet(tester);
      expect(server.calls, contains('PATCH /rest/v1/user_profiles'),
          reason: 'premise');
      expect(find.text(_sheetSaved), findsNothing,
          reason: 'THE defect: nothing was saved and the coach was told it '
              'was');
      expect(_inSheet(_sheetZeroRows), findsOneWidget,
          reason: 'U1: a SnackBar on the page sits under the modal sheet');
      expect(find.text('Save price'), findsOneWidget,
          reason: 'the sheet stays open to try again');
      expect(_fieldText(tester), '150', reason: 'the entered price is kept');
    });

    testWidgets('a failed save stops the spinner and says so inside the sheet',
        (tester) async {
      server.mode = _Patch.fails;
      await saveSheet(tester);
      expect(server.calls, contains('PATCH /rest/v1/user_profiles'),
          reason: 'premise');
      expect(find.text(_sheetSaved), findsNothing);
      expect(_inSheet(_generic), findsOneWidget,
          reason: 'U1/U2: inline, and no claim that nothing changed');
      expect(find.text('Save price'), findsOneWidget,
          reason: 'THE defect: the throw escaped _save and the spinner never '
              'stopped');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_fieldText(tester), '150', reason: 'the entered price is kept');
    });

    testWidgets('editing the price clears the inline error', (tester) async {
      server.mode = _Patch.fails;
      await saveSheet(tester);
      expect(_inSheet(_generic), findsOneWidget, reason: 'premise');
      await tester.enterText(find.byType(TextField), '160');
      await tester.pump();
      expect(find.text(_generic), findsNothing);
    });

    for (final price in ['', '0', '-5']) {
      testWidgets('"$price" is refused with an inline reason, nothing written',
          (tester) async {
        await saveSheet(tester, price: price);
        expect(_inSheet(_sheetInvalid), findsOneWidget,
            reason: 'U3b: it used to return silently');
        expect(server.calls.where((c) => c.startsWith('PATCH')), isEmpty,
            reason: 'the rule itself is unchanged');
        expect(find.text('Save price'), findsOneWidget);
      });
    }

    testWidgets('control: a 1-row save says "Pricing updated." and closes',
        (tester) async {
      await saveSheet(tester);
      expect(find.text(_sheetSaved), findsOneWidget);
      expect(find.text('Save price'), findsNothing);
    });
  });

  group('Set Custom Price dialog', () {
    Future<void> saveDialog(WidgetTester tester, {String price = '150'}) async {
      await host(tester, (c) => showCustomPriceDialogForTest(c, 'client-1'));
      await tester.enterText(find.byType(TextField), price);
      await tester.tap(find.text('Save'));
      await settle(tester);
    }

    TextButton saveButton(WidgetTester tester) => tester.widget<TextButton>(find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextButton))
        .last);

    testWidgets(
        'a 0-row save says there is no relationship INSIDE the dialog, not '
        '"Custom price set"', (tester) async {
      server.mode = _Patch.zeroRows;
      await saveDialog(tester);
      expect(
          server.calls, contains('PATCH /rest/v1/coach_client_relationships'),
          reason: 'premise');
      expect(find.text(_dialogSaved), findsNothing,
          reason: 'THE defect: "Custom price set to \$150/mo." while checkout '
              'kept charging the standard rate');
      expect(_inDialog(_dialogNoRelationship), findsOneWidget,
          reason: 'U1: a SnackBar on the page sits under the dialog scrim');
      expect(find.text('Custom Price'), findsOneWidget,
          reason: 'the dialog stays open');
      expect(_fieldText(tester), '150', reason: 'the entered price is kept');
    });

    testWidgets(
        'a failed save shows the generic message inside the dialog '
        'and re-enables Save', (tester) async {
      server.mode = _Patch.fails;
      await saveDialog(tester);
      expect(find.text(_dialogSaved), findsNothing);
      expect(_inDialog(_generic), findsOneWidget);
      expect(_fieldText(tester), '150', reason: 'the entered price is kept');
      expect(saveButton(tester).onPressed, isNotNull,
          reason: 'U3: Save is usable again after a failure');
    });

    testWidgets('an unreadable price is refused inside the dialog',
        (tester) async {
      await saveDialog(tester, price: '150/mo');
      expect(_inDialog(_dialogParseError), findsOneWidget,
          reason: 'U1: the parse error was also a SnackBar under the scrim');
      expect(server.calls.where((c) => c.startsWith('PATCH')), isEmpty);
      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      expect(find.text(_dialogParseError), findsNothing,
          reason: 'editing clears the error');
    });

    testWidgets('Save is disabled with a spinner while the write is in flight',
        (tester) async {
      server.gate = Completer<void>();
      await saveDialog(tester);
      expect(
          server.calls
              .where((c) => c == 'PATCH /rest/v1/coach_client_relationships'),
          hasLength(1),
          reason: 'premise: the write is waiting on the gate');
      expect(saveButton(tester).onPressed, isNull,
          reason: 'U3: a second tap would send a second write');
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      server.gate!.complete();
      await settle(tester);
      expect(find.text(_dialogSaved), findsOneWidget);
      expect(find.text('Custom Price'), findsNothing);
    });

    testWidgets('control: a 1-row save says "Custom price set" and closes',
        (tester) async {
      await saveDialog(tester);
      expect(find.text(_dialogSaved), findsOneWidget);
      expect(find.text('Custom Price'), findsNothing);
    });
  });
}
