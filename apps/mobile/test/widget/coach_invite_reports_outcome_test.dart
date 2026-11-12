import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The coach dashboard's "Invite a Client" sheet said "Invite sent!" whatever
// happened.
//
//   * `CoachRelationshipService.sendInvite` saved the invite row, then called
//     `send-invite-email` inside `catch (_) {}`. A failed email — the function
//     answers 5xx when Resend refuses or email is not configured — was
//     swallowed, and the coach was told the client had been sent an invite
//     that never left.
//   * A failed insert threw out of the button with nothing caught: no message,
//     and the sheet's spinner never stopped.
//   * After a send that worked, SENT INVITES was not re-read, so the new
//     invite was not listed.

const _uid = '00000000-0000-4000-8000-0000000c1a5e';
const _sent = 'Invite sent!';
const _failed = "Couldn't send the invite — check your connection and try again.";

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

/// Answers like PostgREST and the Functions endpoint.
class _Server extends http.BaseClient {
  bool insertFails = false;
  bool emailFails = false;
  final calls = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path.endsWith('/coach_invites') && request.method == 'POST') {
      return insertFails
          ? _json({'message': 'offline'}, 500, request)
          : _json({'id': 'inv-1', 'token': 'tok-1'}, 201, request);
    }
    if (path.endsWith('/send-invite-email')) {
      return emailFails
          ? _json({'error': 'Email send failed'}, 502, request)
          : _json({'sent': true}, 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  var inviteReads = 0;

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
        // No deep-link listener: `runAsync` below lets real time pass, and
        // app_links has no platform implementation in a test.
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..insertFails = false
      ..emailFails = false
      ..calls.clear();
    inviteReads = 0;
  });

  /// Opens the sheet from the Requests tab and sends one invite. Every list
  /// the dashboard reads is overridden; only the invite reaches the server.
  Future<void> invite(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
        coachClientsProvider.overrideWith((ref) async => const []),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
        coachAiSignalsProvider.overrideWith((ref) async => const []),
        sentInvitesProvider.overrideWith((ref) async {
          inviteReads++;
          return const [];
        }),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.tap(find.text('Requests').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Invite Client by Email'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).last, 'new.client@example.com');
    await tester.tap(find.text('Send Invite'));
    // The Functions client encodes and decodes JSON on a real isolate, which
    // the test's fake clock cannot advance; let real time pass for it.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('an invite whose email failed is not "Invite sent!"', (tester) async {
    server.emailFails = true;
    await invite(tester);

    expect(server.calls, contains('POST /functions/v1/send-invite-email'), reason: 'premise');
    expect(find.text(_sent), findsNothing,
        reason: 'THE defect: the email failed and was swallowed; the client '
            'was never sent anything');
    expect(find.text(_failed), findsOneWidget);
    expect(find.text('Send Invite'), findsOneWidget,
        reason: 'the sheet stays open to try again');
  });

  testWidgets('a failed insert says so and stops the spinner', (tester) async {
    server.insertFails = true;
    await invite(tester);

    expect(find.text(_sent), findsNothing);
    expect(find.text(_failed), findsOneWidget);
    expect(find.text('Send Invite'), findsOneWidget,
        reason: 'THE defect: the throw escaped the button and the spinner '
            'never stopped');
    expect(server.calls, isNot(contains('POST /functions/v1/send-invite-email')));
  });

  testWidgets('control: an invite that was sent says so', (tester) async {
    await invite(tester);
    expect(find.text(_sent), findsOneWidget);
    expect(find.text(_failed), findsNothing);
  });

  testWidgets('a sent invite is listed under SENT INVITES', (tester) async {
    await invite(tester);
    expect(inviteReads, greaterThanOrEqualTo(2),
        reason: 'the list was read on opening and must be read again after '
            'the send');
  });
}
