import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coaching_mode/domain/coaching_mode_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Switching coaching mode left the old plan on screen.
//
// `setMode` saves the mode, then runs `generate_client_plan` (Self/AI-Guided) or
// `deactivate_self_generated_plan` (Coach-Guided). Those replace the member's
// habits, nutrition targets and program assignment (121; 047) and send no
// notification, so the re-reads a coach's assignment triggers never ran: Habits
// kept listing deactivated habits, Nutrition and Meals kept the old targets,
// and the program stayed as it was. Only the plan label and workouts re-read.

const _uid = '00000000-0000-4000-8000-0000000000d7';

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
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Object? body = [];
    final path = request.url.path;
    if (path.endsWith('/user_profiles')) {
      body = request.method == 'PATCH' ? [{'id': _uid}] : [{'coaching_mode': 'coach_guided'}];
      if (request.headers['Accept']?.contains('vnd.pgrst.object') ?? false) {
        body = {'coaching_mode': 'coach_guided'};
      }
    } else if (path.contains('/rpc/')) {
      body = null;
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test("switching to Self-Guided re-reads the habits, targets and program it replaced", () async {
    final reads = <String, int>{};
    Future<T> counted<T>(String k, T v) async {
      reads[k] = (reads[k] ?? 0) + 1;
      return v;
    }

    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      myHabitsProvider.overrideWith((ref) => counted('habits', const <Map<String, dynamic>>[])),
      nutritionGoalsProvider.overrideWith((ref) => counted('targets', const <String, double>{})),
      myNutritionPlanProvider.overrideWith((ref) => counted('nutrition plan', null)),
      myAssignedProgramProvider.overrideWith((ref) => counted('program', null)),
    ]);
    addTearDown(c.dispose);
    for (final p in <ProviderListenable<Object?>>[
      myHabitsProvider, nutritionGoalsProvider, myNutritionPlanProvider, myAssignedProgramProvider,
    ]) {
      c.listen<Object?>(p, (_, __) {});
    }
    c.listen(coachingModeNotifierProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final before = Map.of(reads);

    await c.read(coachingModeNotifierProvider.notifier).setMode(CoachingMode.selfGuided);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(myHabitsProvider.future);
    await c.read(nutritionGoalsProvider.future);
    await c.read(myNutritionPlanProvider.future);
    await c.read(myAssignedProgramProvider.future);

    for (final k in before.keys) {
      expect(reads[k], greaterThan(before[k]!),
          reason: 'THE defect: $k kept the plan the switch had just replaced');
    }
  });
}
