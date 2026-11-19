import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-14 · Manage Availability told the truth only when everything worked.
//
//  * `_load` ended `catch (_) { _loading = false; }` with the lists still
//    empty, so a failed read of coach_availability / coaching_calls was drawn
//    as "No availability published" and no upcoming sessions — a coach told
//    their calendar was empty.
//  * `_delete` awaited a bare `.delete().eq('id', id)`: a thrown failure was
//    unhandled and said nothing, and a delete that removed NO row (RLS filters
//    silently; PostgREST answers 204 either way when no rows are asked for)
//    passed as done.

const _uid = '00000000-0000-4000-8000-0000000a7a11';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
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

enum _Delete { oneRow, zeroRows, serverError, network }

/// PostgREST as it answers these calls. A DELETE that does not ask for rows
/// back (`select=` absent) gets 204 with no body — which is also exactly what
/// a 0-row delete looks like.
class _Server extends http.BaseClient {
  bool readsFail = false;
  bool readsNetwork = false;
  _Delete deleteMode = _Delete.oneRow;
  final slots = <Map<String, Object?>>[];
  final deletes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    if (request.method == 'DELETE') {
      deletes.add('${request.url.path}?${request.url.query}');
      final asksForRows = q.containsKey('select');
      switch (deleteMode) {
        case _Delete.network:
          throw http.ClientException('Connection refused', request.url);
        case _Delete.serverError:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case _Delete.zeroRows:
          return asksForRows ? _json([], 200, request) : _empty(request);
        case _Delete.oneRow:
          final id = (q['id'] ?? '').replaceFirst('eq.', '');
          slots.removeWhere((s) => s['id'] == id);
          return asksForRows ? _json([{'id': id}], 200, request) : _empty(request);
      }
    }
    if (path.endsWith('/coach_availability') || path.endsWith('/coaching_calls')) {
      if (readsNetwork) throw http.ClientException('Connection refused', request.url);
      if (readsFail) return _json({'message': 'boom', 'code': 'XX000'}, 500, request);
      return _json(path.endsWith('/coach_availability') ? slots : const [], 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _empty(http.BaseRequest r) =>
      http.StreamedResponse(const Stream.empty(), 204, request: r);

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

String _at(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + days, 10).toUtc().toIso8601String();
}

Map<String, Object?> _slot(String id) => {
      'id': id, 'coach_id': _uid, 'slot_time': _at(2),
      'duration_minutes': 30, 'type': 'consultation', 'is_booked': false,
    };

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
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..readsFail = false
      ..readsNetwork = false
      ..deleteMode = _Delete.oneRow
      ..deletes.clear()
      ..slots.clear();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await tester.pumpAndSettle();
  }

  group('a failed load', () {
    testWidgets('is said, not drawn as an empty calendar', (tester) async {
      server.readsFail = true;
      await open(tester);

      expect(find.textContaining("Couldn't load your availability"), findsOneWidget,
          reason: 'THE defect: a failed read rendered as "no slots"');
      expect(find.text('No availability published'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      // A server refusal is not a connection problem.
      expect(find.textContaining('check your connection'), findsNothing);
      expect(find.textContaining('contact support'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing, reason: 'no exception text');
      expect(reported.map((f) => f.origin), contains('CoachAvailabilityScreen._load'));
    });

    testWidgets('a connection failure says to check the connection', (tester) async {
      server.readsNetwork = true;
      await open(tester);
      expect(find.textContaining("Couldn't load your availability — check your connection"),
          findsOneWidget);
    });

    testWidgets('Try again reads again and shows the slots', (tester) async {
      server.readsFail = true;
      await open(tester);
      server
        ..readsFail = false
        ..slots.add(_slot('s-1'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load your availability"), findsNothing);
      expect(find.text('Strategy Consultation'), findsOneWidget);
    });

    testWidgets('control: a real empty calendar keeps its empty state', (tester) async {
      await open(tester);
      expect(find.text('No availability published'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
    });
  });

  group('removing a slot', () {
    Future<void> openWithSlot(WidgetTester tester) async {
      server.slots.add(_slot('s-1'));
      await open(tester);
      expect(find.text('Strategy Consultation'), findsOneWidget);
    }

    testWidgets('a delete that removed no row is a failure, said on the page',
        (tester) async {
      await openWithSlot(tester);
      server.deleteMode = _Delete.zeroRows;
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(server.deletes.single, contains('select=id'),
          reason: 'the delete must ask for its row back to know one went');
      expect(find.textContaining("Couldn't remove this slot — nothing was changed"),
          findsOneWidget,
          reason: 'THE defect: a 0-row delete (204) passed as done');
      expect(find.text('Strategy Consultation'), findsOneWidget);
    });

    testWidgets('a delete that failed is reported and said, not swallowed',
        (tester) async {
      await openWithSlot(tester);
      server.deleteMode = _Delete.serverError;
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't remove this slot — try again in a moment"),
          findsOneWidget);
      expect(find.textContaining('refused'), findsNothing, reason: 'no exception text');
      expect(reported.map((f) => f.origin), contains('CoachAvailabilityScreen._delete'));
      expect(find.text('Strategy Consultation'), findsOneWidget);
    });

    testWidgets('a delete that never reached the server says to check the connection',
        (tester) async {
      await openWithSlot(tester);
      server.deleteMode = _Delete.network;
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't remove this slot — check your connection"),
          findsOneWidget);
    });

    testWidgets('control: a delete that removed the row reloads without a failure',
        (tester) async {
      await openWithSlot(tester);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.text('Strategy Consultation'), findsNothing);
      expect(find.text('No availability published'), findsOneWidget);
    });
  });
}
