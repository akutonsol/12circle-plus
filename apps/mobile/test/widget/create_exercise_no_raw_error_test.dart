import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart';
import 'package:circle_fitness/features/workout/data/models/video_variant_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-5 · C · saving an exercise never shows raw database text.
//
// At 918c8dc `_friendlyError` pulled the `message:` out of any PostgREST /
// Storage exception and showed it: "Save failed: new row violates row-level
// security policy for table …", and the same after "Saved, but not sent for
// review:". Only messages the app wrote on purpose (a StateError's message,
// the plain String the service stores as lastError) may still be shown.
//
// The exercise service is faked; Supabase is initialised signed out only
// because the save path reads `auth.currentUser`. Nothing is sent.

const _secretMsg =
    'new row violates row-level security policy for table SECRET_TABLE_X';
final _secret = PostgrestException(message: _secretMsg, code: '42501');

class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
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

class _Svc extends CustomExerciseService {
  /// What createExercise leaves in lastError when it fails; null = it succeeds.
  Object? createFails;
  bool createFailsSilently = false;

  /// What reviewExercise leaves in lastError when it fails; null = it succeeds.
  Object? reviewFails;
  bool reviewFailsSilently = false;
  final reviewed = <String>[];

  @override
  Future<List<ExerciseDetail>> getMyExercises() async => const [];

  @override
  Future<String?> createExercise({
    required String name,
    required String category,
    required String muscleGroup,
    required List<String> secondaryMuscles,
    required String equipment,
    required String difficulty,
    required String description,
    required List<String> instructions,
    required List<String> coachingCues,
    required List<String> commonMistakes,
    required List<String> alternatives,
    String? beginnerModification,
    String? advancedProgression,
    required List<String> tags,
    required List<VideoVariant> videoVariants,
    String? imageUrl,
    String visibility = 'private',
    Map<String, dynamic>? extra,
  }) async {
    lastError = null;
    if (createFailsSilently) return null;
    if (createFails != null) {
      lastError = createFails;
      return null;
    }
    return 'new-1';
  }

  @override
  Future<Map<String, dynamic>?> getRawById(String id) async => {
        'id': id,
        'name': 'Goblet Squat',
        'coach_id': null,
        'content_status': 'draft',
        'visibility': 'global',
        'instructions': ['Brace and sit down between the heels'],
      };

  @override
  Future<bool> updateExercise(String id, Map<String, dynamic> updates) async =>
      true;

  @override
  Future<bool> reviewExercise(String id, String status) async {
    reviewed.add(status);
    if (reviewFailsSilently) return false;
    if (reviewFails != null) {
      lastError = reviewFails;
      return false;
    }
    return true;
  }

  @override
  Future<bool> syncRelations(String exerciseId, Map<String, dynamic> j) async =>
      true;
}

Widget _screen(_Svc svc, {String? editing, String role = 'coach'}) =>
    ProviderScope(
      overrides: [
        customExerciseSvcProvider.overrideWithValue(svc),
        currentUserProfileProvider.overrideWith((ref) async => {'role': role}),
        editingExerciseProvider.overrideWith((ref) => editing),
      ],
      child: const MaterialApp(home: CreateExerciseScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _createAndSave(WidgetTester tester, _Svc svc) async {
  await tester.pumpWidget(_screen(svc));
  await _settle(tester);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Exercise Name *'),
    'Goblet Squat',
  );
  await tester.tap(find.text('Save'));
  await _settle(tester);
}

Future<void> _editAsAdminAndSave(WidgetTester tester, _Svc svc) async {
  await tester.pumpWidget(_screen(svc, editing: 'ex-1', role: 'admin'));
  await _settle(tester);
  expect(find.text('Edit Exercise'), findsOneWidget);
  await tester.tap(find.text('Save'));
  await _settle(tester);
}

void _noRawText() {
  expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
  expect(find.textContaining('row-level security'), findsNothing);
  expect(find.textContaining('Exception'), findsNothing);
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _NoNetwork(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  late List<AppFailure> reported;
  setUp(() {
    reported = [];
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  testWidgets(
      'a database failure on save is stated in plain words; the raw '
      'message is recorded, not shown', (tester) async {
    final svc = _Svc()..createFails = _secret;
    await _createAndSave(tester, svc);

    _noRawText(); // the defect first: the RLS message was on screen
    expect(
      find.text(
        "Couldn't save the exercise — check your connection and try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Exercise Saved!'), findsNothing);
    expect(reported.map((f) => f.origin), ['CreateExerciseScreen.save']);
    expect(reported.single.error, same(_secret));
  });

  testWidgets('a save that failed with no error recorded gets the same copy', (
    tester,
  ) async {
    final svc = _Svc()..createFailsSilently = true;
    await _createAndSave(tester, svc);
    expect(
      find.text(
        "Couldn't save the exercise — check your connection and try again.",
      ),
      findsOneWidget,
    );
    expect(reported, isEmpty, reason: 'nothing to record');
  });

  testWidgets('control: a StateError the app wrote is still shown as-is', (
    tester,
  ) async {
    final svc = _Svc()
      ..createFails = StateError('An exercise needs a name before it saves');
    await _createAndSave(tester, svc);
    expect(
      find.text('Save failed: An exercise needs a name before it saves'),
      findsOneWidget,
    );
  });

  testWidgets('control: the service\'s own String message is still shown', (
    tester,
  ) async {
    final svc = _Svc()
      ..createFails = "You don't have permission to edit this exercise";
    await _createAndSave(tester, svc);
    expect(
      find.text("Save failed: You don't have permission to edit this exercise"),
      findsOneWidget,
    );
  });

  testWidgets(
      'a failed review submission says "Saved, but not sent for '
      'review" without the database text', (tester) async {
    final svc = _Svc()..reviewFails = _secret;
    await _editAsAdminAndSave(tester, svc);

    expect(svc.reviewed, ['under_review']);
    _noRawText(); // the defect first: the RLS message was on screen
    expect(
      find.text(
        'Saved, but not sent for review — try submitting again from the '
        'exercise.',
      ),
      findsOneWidget,
    );
    expect(find.text('Exercise Saved!'), findsOneWidget,
        reason: 'the save itself succeeded and still says so');
    expect(reported.map((f) => f.origin),
        ['CreateExerciseScreen.submitForReview']);
  });

  testWidgets(
      'a review submission that failed with no error recorded no '
      'longer says "unknown error"', (tester) async {
    final svc = _Svc()..reviewFailsSilently = true;
    await _editAsAdminAndSave(tester, svc);
    expect(
      find.text(
        'Saved, but not sent for review — try submitting again from the '
        'exercise.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('unknown error'), findsNothing);
  });

  testWidgets('control: a StateError on review submission is shown as-is', (
    tester,
  ) async {
    final svc = _Svc()..reviewFails = StateError('Add a video first');
    await _editAsAdminAndSave(tester, svc);
    expect(
      find.text('Saved, but not sent for review: Add a video first'),
      findsOneWidget,
    );
  });

  testWidgets('success is unchanged: the saved dialog, no failure copy', (
    tester,
  ) async {
    final svc = _Svc();
    await _createAndSave(tester, svc);
    expect(find.text('Exercise Saved!'), findsOneWidget);
    expect(find.textContaining('Save failed'), findsNothing);
    expect(find.textContaining("Couldn't save"), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets('success with review submission: no review snackbar', (
    tester,
  ) async {
    final svc = _Svc();
    await _editAsAdminAndSave(tester, svc);
    expect(svc.reviewed, ['under_review']);
    expect(find.text('Exercise Saved!'), findsOneWidget);
    expect(find.textContaining('not sent for review'), findsNothing);
  });
}
