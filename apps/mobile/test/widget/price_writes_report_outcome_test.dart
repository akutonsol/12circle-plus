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

const _uid = '00000000-0000-4000-8000-0000000b1ce2';
const _sheetSaved = 'Pricing updated. Clients will see your new rate.';
const _sheetGeneric = "Couldn't save your price — try again.";
const _dialogSaved = r'Custom price set to $150/mo.';

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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add('${request.method} ${request.url.path}');
    if (request.method == 'PATCH') {
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
    Future<void> saveSheet(WidgetTester tester) async {
      await host(tester, showCoachPricingSheet);
      expect(find.text('Save price'), findsOneWidget, reason: 'premise');
      await tester.enterText(find.byType(TextField), '150');
      await tester.tap(find.text('Save price'));
      await settle(tester);
      expect(server.calls, contains('PATCH /rest/v1/user_profiles'),
          reason: 'premise');
    }

    testWidgets('a 0-row save says nothing changed, not "Pricing updated."',
        (tester) async {
      server.mode = _Patch.zeroRows;
      await saveSheet(tester);
      expect(find.text(_sheetSaved), findsNothing,
          reason: 'THE defect: nothing was saved and the coach was told it '
              'was');
      expect(find.textContaining('nothing was changed'), findsOneWidget);
      expect(find.text('Save price'), findsOneWidget,
          reason: 'the sheet stays open to try again');
    });

    testWidgets('a failed save stops the spinner and says so', (tester) async {
      server.mode = _Patch.fails;
      await saveSheet(tester);
      expect(find.text(_sheetSaved), findsNothing);
      expect(find.text(_sheetGeneric), findsOneWidget);
      expect(find.text('Save price'), findsOneWidget,
          reason: 'THE defect: the throw escaped _save and the spinner never '
              'stopped');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('control: a 1-row save says "Pricing updated." and closes',
        (tester) async {
      await saveSheet(tester);
      expect(find.text(_sheetSaved), findsOneWidget);
      expect(find.text('Save price'), findsNothing);
    });
  });

  group('Set Custom Price dialog', () {
    Future<void> saveDialog(WidgetTester tester) async {
      await host(tester, (c) => showCustomPriceDialogForTest(c, 'client-1'));
      await tester.enterText(find.byType(TextField), '150');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(
          server.calls, contains('PATCH /rest/v1/coach_client_relationships'),
          reason: 'premise');
    }

    testWidgets(
        'a 0-row save says there is no relationship, not "Custom price set"',
        (tester) async {
      server.mode = _Patch.zeroRows;
      await saveDialog(tester);
      expect(find.text(_dialogSaved), findsNothing,
          reason: 'THE defect: "Custom price set to \$150/mo." while checkout '
              'kept charging the standard rate');
      expect(
          find.text(
              'No coaching relationship with this client — nothing was changed.'),
          findsOneWidget);
      expect(find.text('Custom Price'), findsOneWidget,
          reason: 'the dialog stays open');
    });

    testWidgets('a failed save keeps the generic message', (tester) async {
      server.mode = _Patch.fails;
      await saveDialog(tester);
      expect(find.text(_dialogSaved), findsNothing);
      expect(find.text("Couldn't save the price — try again."), findsOneWidget);
    });

    testWidgets('control: a 1-row save says "Custom price set" and closes',
        (tester) async {
      await saveDialog(tester);
      expect(find.text(_dialogSaved), findsOneWidget);
      expect(find.text('Custom Price'), findsNothing);
    });
  });
}
