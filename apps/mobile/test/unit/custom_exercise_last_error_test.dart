import 'dart:convert';

import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-5 follow-up · S3 · a call never leaves an EARLIER call's error behind.
//
// At a9e69be createExercise returned null for a signed-out user before it
// cleared lastError, and updateExercise / reviewExercise never cleared it, so
// a stale failure from a previous call was read (and recorded / shown) as the
// current one's. The real service runs against a fake PostgREST that answers
// every request with one row; nobody is signed in.

class _OneRow extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[{"id":"ex-1"}]')),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
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

final _stale = StateError('stale error from an earlier call');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _OneRow(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('createExercise signed out returns null with lastError cleared',
      () async {
    final svc = CustomExerciseService()..lastError = _stale;
    final id = await svc.createExercise(
      name: 'Goblet Squat',
      category: 'Strength',
      muscleGroup: 'Legs',
      secondaryMuscles: const [],
      equipment: 'Dumbbell',
      difficulty: 'Beginner',
      description: '',
      instructions: const [],
      coachingCues: const [],
      commonMistakes: const [],
      alternatives: const [],
      tags: const [],
      videoVariants: const [],
    );
    expect(id, isNull);
    expect(svc.lastError, isNull,
        reason: 'the stale error must not be read as this failure');
  });

  test('a successful updateExercise clears an earlier error', () async {
    final svc = CustomExerciseService()..lastError = _stale;
    expect(await svc.updateExercise('ex-1', {'name': 'x'}), isTrue);
    expect(svc.lastError, isNull);
  });

  test('a successful reviewExercise clears an earlier error', () async {
    final svc = CustomExerciseService()..lastError = _stale;
    expect(await svc.reviewExercise('ex-1', 'under_review'), isTrue);
    expect(svc.lastError, isNull);
  });
}
