import 'dart:convert';

import 'package:circle_fitness/features/ai_coach/data/ai_coach_service.dart';
import 'package:circle_fitness/features/ai_coach/presentation/ai_coach_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "Coach style updated" was said for a style that was never saved.
//
// `setPersona` answers false when the write fails; the AI Coach's style card
// ignored it, kept the new style highlighted and said "Coach style updated —
// your next brief will match."

class _Svc extends AICoachService {
  _Svc(this.saves);
  final bool saves;
  @override
  Future<bool> setPersona({required String style, required String tone, String name = 'Nova'}) async =>
      saves;
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

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Offline(),
      authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _MemoryStore(),
          detectSessionInUri: false),
      debug: false,
    );
  });

  test('a style that was not saved is not reported as updated', () async {
    final r = await changeCoachStyle(_Svc(false), style: 'calm', tone: 'calm');
    expect(r.saved, isFalse);
    expect(r.message, isNot(contains('updated')),
        reason: 'THE defect: "Coach style updated" for a failed save');
  });

  test('control: a saved style is reported as updated', () async {
    final r = await changeCoachStyle(_Svc(true), style: 'calm', tone: 'calm');
    expect(r.saved, isTrue);
    expect(r.message, contains('updated'));
  });
}
