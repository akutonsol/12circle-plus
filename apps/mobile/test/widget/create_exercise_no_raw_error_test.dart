import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
//
// Follow-up (review U1/U2/S3): the connection hint is kept for network
// failures only; anything else gets the plain "contact support" copy; a save
// with nobody signed in says so; a failed review submission says it is still
// owed (there is no separate "submit for review" control to point at).

const _network =
    "Couldn't save the exercise — check your connection and try again.";
const _generic =
    "Couldn't save the exercise. Try again — if it keeps happening, contact "
    'support.';
const _signedOut = "You're signed out — sign in again to save.";
const _reviewGeneric =
    'Saved, but not sent for review yet — it still needs to be submitted for '
    'review.';
const _reviewNetwork =
    'Saved, but not sent for review yet — check your connection. It still '
    'needs to be submitted for review.';

final _user = User(
  id: '00000000-0000-0000-0000-0000000000c1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-16T00:00:00Z',
);

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

Widget _screen(
  _Svc svc, {
  String? editing,
  String role = 'coach',
  bool signedIn = true,
}) =>
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(signedIn ? _user : null),
        customExerciseSvcProvider.overrideWithValue(svc),
        // P0-FL-45b: the real read selects `id`; a role counts only for the
        // member it was read for.
        currentUserProfileProvider
            .overrideWith((ref) async => {'id': _user.id, 'role': role}),
        editingExerciseProvider.overrideWith((ref) => editing),
      ],
      child: const MaterialApp(home: CreateExerciseScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _createAndSave(
  WidgetTester tester,
  _Svc svc, {
  bool signedIn = true,
}) async {
  await tester.pumpWidget(_screen(svc, signedIn: signedIn));
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
    // U1: a refusal is not a connection problem.
    expect(find.text(_generic), findsOneWidget);
    expect(find.text(_network), findsNothing);
    expect(find.text('Exercise Saved!'), findsNothing);
    expect(reported.map((f) => f.origin), ['CreateExerciseScreen.save']);
    expect(reported.single.error, same(_secret));
  });

  testWidgets('a save that failed with no error recorded gets the same copy', (
    tester,
  ) async {
    final svc = _Svc()..createFailsSilently = true;
    await _createAndSave(tester, svc);
    expect(find.text(_generic), findsOneWidget);
    expect(find.text(_network), findsNothing);
    expect(reported, isEmpty, reason: 'nothing to record');
  });

  for (final c in <(String, Object)>[
    ('SocketException', const SocketException('Failed host lookup')),
    ('TimeoutException', TimeoutException('no answer')),
    ('http ClientException', http.ClientException('Connection closed')),
    ('AuthRetryableFetchException', AuthRetryableFetchException()),
  ]) {
    testWidgets('U1 a network failure (${c.$1}) keeps the connection hint', (
      tester,
    ) async {
      final svc = _Svc()..createFails = c.$2;
      await _createAndSave(tester, svc);
      expect(find.text(_network), findsOneWidget);
      expect(find.text(_generic), findsNothing);
      expect(reported.map((f) => f.origin), ['CreateExerciseScreen.save']);
    });
  }

  for (final c in <(String, Object)>[
    ('unique violation', const PostgrestException(
        message: 'duplicate key value violates unique constraint', code: '23505')),
    ('a gateway status', const PostgrestException(message: 'Bad gateway', code: '502')),
    ('a FormatException', const FormatException('bad json')),
  ]) {
    testWidgets('U1 a non-network failure (${c.$1}) gets the support copy', (
      tester,
    ) async {
      final svc = _Svc()..createFails = c.$2;
      await _createAndSave(tester, svc);
      expect(find.text(_generic), findsOneWidget);
      expect(find.text(_network), findsNothing);
      expect(find.textContaining('duplicate key'), findsNothing);
    });
  }

  testWidgets('S3 a save with nobody signed in says so', (tester) async {
    // The real service returns null with lastError cleared when signed out.
    final svc = _Svc()..createFailsSilently = true;
    await _createAndSave(tester, svc, signedIn: false);
    expect(find.text(_signedOut), findsOneWidget);
    expect(find.text(_network), findsNothing);
    expect(find.text(_generic), findsNothing);
    expect(find.text('Exercise Saved!'), findsNothing);
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
    // U2: no resubmit control exists, so the copy names what is still owed.
    expect(find.text(_reviewGeneric), findsOneWidget);
    expect(find.textContaining('check your connection'), findsNothing);
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
    expect(find.text(_reviewGeneric), findsOneWidget);
    expect(find.textContaining('unknown error'), findsNothing);
  });

  testWidgets('U1 a review submission lost to the network keeps the hint', (
    tester,
  ) async {
    final svc = _Svc()
      ..reviewFails = http.ClientException('Connection reset by peer');
    await _editAsAdminAndSave(tester, svc);
    expect(find.text(_reviewNetwork), findsOneWidget);
    expect(find.text(_reviewGeneric), findsNothing);
    expect(find.text('Exercise Saved!'), findsOneWidget);
    expect(reported.map((f) => f.origin),
        ['CreateExerciseScreen.submitForReview']);
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
