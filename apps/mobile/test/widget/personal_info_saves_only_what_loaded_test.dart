import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Personal Info saved a blank form over the client's real details.
//
// `currentUserProfileProvider` returns null when its read fails. The screen then
// leaves every field empty (and `_loaded` false) but Save was not gated on it:
// `buildPersonalInfoPayload` sends a cleared field as null by design, so typing a
// first name and tapping Save wrote null height, weight, goal weight, phone and
// gender over the stored values — and said "Profile updated successfully".

const _uid = '00000000-0000-4000-8000-0000000000b1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

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

class _Server extends http.BaseClient {
  final List<Map<String, Object?>> patches = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/user_profiles') && request.method == 'PATCH') {
      patches.add(Map<String, Object?>.from(
          jsonDecode(await request.finalize().bytesToString()) as Map));
    }
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
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

  setUp(() => server.patches.clear());

  Future<void> open(WidgetTester tester, Map<String, dynamic>? profile) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserProfileProvider.overrideWith((ref) async => profile)],
      child: const MaterialApp(home: PersonalInfoScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a profile that failed to load is never saved over', (tester) async {
    await open(tester, null); // the provider's answer to a failed read
    await tester.enterText(find.byType(TextField).first, 'Jordan');
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(server.patches, isEmpty,
        reason: 'THE defect: Save sent null height/weight/goal/phone/gender over the real ones');
    expect(find.textContaining('nothing was saved'), findsOneWidget);
    expect(find.text('Profile updated successfully'), findsNothing);
  });

  testWidgets('control: a loaded profile saves what the form shows', (tester) async {
    await open(tester, {
      'first_name': 'Jordan', 'last_name': 'Lee', 'role': 'client',
      'height_cm': 180, 'weight_kg': 82.5, 'weight_goal_kg': 78.0,
      'gender': 'female', 'training_days_per_week': 4,
    });
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(server.patches, hasLength(1));
    expect(server.patches.single['weight_kg'], 82.5);
    expect(server.patches.single['gender'], 'female');
  });
}
