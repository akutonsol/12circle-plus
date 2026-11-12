import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Settings › Coaching Mode. Self- and AI-Guided include no coach, so leaving
// Coach-Guided for one of them asks "End coaching with Coach …?" and ends the
// relationship first. Whether there is a coach to end came from one read:
//
//   try { coaches = await ref.read(myCoachesProvider.future); } catch (_) {}
//
// and a failed read left `coaches` empty — "no coach". The question was never
// asked, nothing was ended, and the mode switched anyway: the client was told
// they were Self-Guided while their coaching (and its billing) went on. The
// same switch went ahead past an `End & switch` whose cancellation failed
// with the spinner left running for good.
//
// Now neither changes the mode. The sheet stays open with the message it
// already shows when the mode itself cannot be saved.

const _uid = '00000000-0000-4000-8000-00000000d0de';

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

/// Answers like PostgREST for a client who is Coach-Guided with one active
/// coach, unless told the relationships read or the cancellation fails.
class _Server extends http.BaseClient {
  bool relationshipsReadFails = false;
  bool cancelFails = false;
  bool hasCoach = true;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';
    if (request.method != 'GET') writes.add('${request.method} $path $body');
    if (path.endsWith('/coach_client_relationships')) {
      if (request.method == 'GET') {
        if (relationshipsReadFails) {
          return _json({'message': 'offline'}, 500, request);
        }
        return _json([
          if (hasCoach)
            {'id': 'rel-1', 'coach_id': 'coach-a', 'status': 'active'},
        ], 200, request);
      }
      if (cancelFails) return _json({'message': 'offline'}, 500, request);
      return _json([], 200, request);
    }
    if (path.endsWith('/public_profiles')) {
      return _json([
        {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'},
      ], 200, request);
    }
    if (path.endsWith('/user_profiles') && request.method == 'PATCH') {
      return _json([{'id': _uid}], 200, request);
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (path.endsWith('/user_profiles')) {
      const me = {'coaching_mode': 'coach_guided', 'first_name': 'Ana',
          'last_name': 'Lee'};
      return _json(single ? me : [me], 200, request);
    }
    return _json(single ? {} : [], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});

  /// Writes that changed the coaching mode.
  List<String> get modeWrites =>
      writes.where((w) => w.contains('coaching_mode')).toList();

  /// Writes that ended a coaching relationship.
  List<String> get cancellations => writes
      .where((w) => w.startsWith('PATCH') && w.contains('coach_client_relationships'))
      .toList();
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
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..relationshipsReadFails = false
      ..cancelFails = false
      ..hasCoach = true
      ..writes.clear();
  });

  /// Opens Settings › Coaching Mode, picks Self Guided and taps Apply.
  Future<void> switchToSelfGuided(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider.overrideWith((ref) async =>
            {'role': 'client', 'first_name': 'Ana', 'last_name': 'Lee'}),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Coach Guided'), findsOneWidget,
        reason: 'guard the premise: the client starts Coach-Guided');
    await tester.tap(find.text('Coach Guided'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Self Guided'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  testWidgets('a FAILED coaches read does not switch the mode', (tester) async {
    server.relationshipsReadFails = true;
    await switchToSelfGuided(tester);

    expect(server.modeWrites, isEmpty,
        reason: 'not knowing whether there is a coach is not "no coach"');
    expect(server.cancellations, isEmpty);
    expect(find.text('Could not save coaching mode.'), findsOneWidget);
    // The sheet stays open, so the choice is not silently lost.
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('a FAILED cancellation does not switch the mode, and the sheet '
      'can be used again', (tester) async {
    server.cancelFails = true;
    await switchToSelfGuided(tester);
    expect(find.text('End coaching with Coach Avery Stone?'), findsOneWidget);
    await tester.tap(find.text('End & switch'));
    await tester.pumpAndSettle();

    expect(server.cancellations, hasLength(1), reason: 'the cancellation was tried');
    expect(server.modeWrites, isEmpty,
        reason: 'coaching did not end, so the client is not Self-Guided');
    expect(find.text('Could not save coaching mode.'), findsOneWidget);
    // Not stuck on a spinner: Apply is back.
    expect(find.text('Apply'), findsOneWidget);
  });

  // ── Controls: what already worked keeps working ──────────────────────────

  testWidgets('an active coach is still asked about, and ended before the '
      'switch', (tester) async {
    await switchToSelfGuided(tester);
    expect(find.text('End coaching with Coach Avery Stone?'), findsOneWidget);
    await tester.tap(find.text('End & switch'));
    await tester.pumpAndSettle();

    expect(server.cancellations, hasLength(1));
    expect(server.modeWrites, hasLength(1));
    expect(find.text('Apply'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('"Keep my coach" still keeps the coach and the mode',
      (tester) async {
    await switchToSelfGuided(tester);
    await tester.tap(find.text('Keep my coach'));
    await tester.pumpAndSettle();

    expect(server.cancellations, isEmpty);
    expect(server.modeWrites, isEmpty);
  });

  testWidgets('a client who really has no coach switches without being asked',
      (tester) async {
    server.hasCoach = false;
    await switchToSelfGuided(tester);

    expect(find.textContaining('End coaching'), findsNothing);
    expect(server.modeWrites, hasLength(1));
    expect(find.text('Could not save coaching mode.'), findsNothing);
  });
}
