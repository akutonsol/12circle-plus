import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-7 · exercise media upload / attach / sync failures are never shown as
// a success.
//
// At 87cda02, after the exercise row saved, the results of uploadImage,
// uploadVideo, updateExerciseMedia, the two updateExercise media writes and
// syncRelations were all ignored and "Exercise Saved!" followed. For a coach's
// media-only edit of a library exercise, nothing at all may have been written.
//
// The exercise service is faked per step; the gallery picker is faked through
// `exerciseMediaPickerProvider` (the only way to put picked bytes on the
// screen without a device). The last group drives the REAL service against a
// fake PostgREST to prove `updateExerciseMedia` now reports the RPC's
// `found = false` (0 rows) as a failure.

const _saved = 'Exercise Saved!';
const _support =
    'Tap Save to try again in a moment. If it keeps happening, contact '
    'support.';
const _network = 'Check your connection, then tap Save to try again.';

final _user = User(
  id: '00000000-0000-0000-0000-0000000000c1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-16T00:00:00Z',
);

final _storageDown = StorageException('bucket refused', statusCode: '403');
final _rls = PostgrestException(message: 'rls refused', code: '42501');
const _zeroRows = "You don't have permission to edit this exercise";

// A valid 1×1 PNG, so the Media tab's preview never trips an image error.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

/// Answers every PostgREST call with [_body] (the RPC's return value).
String _body = '[]';
final _requests = <http.BaseRequest>[];

class _FakeHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(_body)),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
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

class _Picker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      XFile.fromData(_png, name: 'cover.png');

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async =>
      XFile.fromData(Uint8List.fromList([0, 0, 0, 1]), name: 'form.mp4');
}

class _Svc extends CustomExerciseService {
  /// Each knob: what the step leaves in lastError when it fails (null = it
  /// succeeds). `…Silently` fails without recording an error.
  Object? imageUploadFails;
  Object? secondVideoFails;
  Object? mediaRpcFails;
  bool mediaRpcFailsSilently = false;
  Object? imageUrlUpdateFails;
  Object? variantsUpdateFails;
  Object? syncFails;
  bool syncFailsSilently = false;

  /// Library exercise owner for edits (null = a platform exercise).
  String? ownerId;

  final calls = <String>[];
  final writes = <Map<String, dynamic>>[];
  int _videoUploads = 0;

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
    calls.add('create');
    return 'new-1';
  }

  @override
  Future<Map<String, dynamic>?> getRawById(String id) async => {
        'id': id,
        'name': 'Goblet Squat',
        'coach_id': ownerId,
        'content_status': 'approved',
        'visibility': 'private',
        'instructions': ['Brace and sit down between the heels'],
      };

  // Like the real service, these do NOT clear lastError themselves — the
  // screen must, or a failure is reported with an earlier call's error.
  @override
  Future<String?> uploadImage(Uint8List bytes, String ext, String id) async {
    calls.add('uploadImage');
    if (imageUploadFails != null) {
      lastError = imageUploadFails;
      return null;
    }
    return 'https://cdn.test/exercises/$id/image.$ext';
  }

  @override
  Future<String?> uploadVideo(
      Uint8List bytes, String ext, String id, String label) async {
    calls.add('uploadVideo');
    _videoUploads++;
    if (_videoUploads.isEven && secondVideoFails != null) {
      lastError = secondVideoFails;
      return null;
    }
    return 'https://cdn.test/exercises/$id/video_$_videoUploads.$ext';
  }

  @override
  Future<bool> updateExerciseMedia(String id,
      {String? imageUrl,
      required List<Map<String, dynamic>> videoVariants}) async {
    lastError = null;
    calls.add('updateExerciseMedia');
    if (mediaRpcFailsSilently) return false;
    if (mediaRpcFails != null) {
      lastError = mediaRpcFails;
      return false;
    }
    return true;
  }

  @override
  Future<bool> updateExercise(String id, Map<String, dynamic> updates) async {
    lastError = null;
    writes.add(updates);
    Object? fails;
    if (updates.containsKey('image_url')) {
      calls.add('update:image_url');
      fails = imageUrlUpdateFails;
    } else if (updates.containsKey('video_variants')) {
      calls.add('update:video_variants');
      fails = variantsUpdateFails;
    } else {
      calls.add('update:text');
    }
    if (fails != null) {
      lastError = fails;
      return false;
    }
    return true;
  }

  @override
  Future<bool> reviewExercise(String id, String status) async => true;

  @override
  Future<bool> syncRelations(String exerciseId, Map<String, dynamic> j) async {
    calls.add('syncRelations');
    if (syncFailsSilently) return false;
    if (syncFails != null) {
      lastError = syncFails;
      return false;
    }
    return true;
  }
}

Widget _screen(_Svc svc, {String? editing, String role = 'coach'}) =>
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user),
        customExerciseSvcProvider.overrideWithValue(svc),
        currentUserProfileProvider.overrideWith((ref) async => {'role': role}),
        editingExerciseProvider.overrideWith((ref) => editing),
        exerciseMediaPickerProvider.overrideWithValue(_Picker()),
      ],
      child: const MaterialApp(home: CreateExerciseScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, _Svc svc,
    {String? editing, String role = 'coach'}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_screen(svc, editing: editing, role: role));
  await _settle(tester);
  if (editing == null) {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise Name *'), 'Goblet Squat');
  }
  await tester.tap(find.text('MEDIA'));
  await _settle(tester);
}

Future<void> _pickImage(WidgetTester tester) async {
  await tester.tap(find.text('Tap to add image'));
  await _settle(tester);
}

Future<void> _pickVideos(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await _settle(tester);
    await tester.tap(find.text('Upload from device').first);
    await _settle(tester);
  }
  expect(find.text('Video selected'), findsNWidgets(n));
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await _settle(tester);
}

void _notSaved() {
  expect(find.text(_saved), findsNothing,
      reason: 'a failed media step must not end in the success dialog');
  // Kept on the screen so Save can be tapped again.
  expect(find.text('Save'), findsOneWidget);
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _FakeHttp(),
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
    _body = '[]';
    _requests.clear();
  });
  tearDown(resetFailureSink);

  testWidgets('a failed image upload is not "Exercise Saved!"', (tester) async {
    final svc = _Svc()..imageUploadFails = _storageDown;
    await _open(tester, svc);
    await _pickImage(tester);
    await _save(tester);

    _notSaved();
    expect(
        find.text("Exercise saved, but the image couldn't be uploaded. "
            '$_support'),
        findsOneWidget);
    expect(svc.calls, isNot(contains('update:image_url')),
        reason: 'nothing to attach — unchanged');
    expect(reported.map((f) => f.origin), ['CreateExerciseScreen.uploadImage']);
    expect(reported.single.error, same(_storageDown));
  });

  testWidgets(
      'one of two video uploads failing names that video; the other is '
      'still attached', (tester) async {
    final svc = _Svc()
      ..secondVideoFails = http.ClientException('Connection reset by peer');
    await _open(tester, svc);
    await _pickVideos(tester, 2);
    await _save(tester);

    _notSaved();
    expect(
        find.text("Exercise saved, but the Tutorial video couldn't be "
            'uploaded. $_network'),
        findsOneWidget);
    final variants = svc.writes.singleWhere(
        (w) => w.containsKey('video_variants'))['video_variants'] as List;
    expect(variants, hasLength(1), reason: 'what is written is unchanged');
    expect(reported.map((f) => f.origin), ['CreateExerciseScreen.uploadVideo']);
  });

  testWidgets('a failed image_url write (0 rows) is not "Exercise Saved!"',
      (tester) async {
    final svc = _Svc()..imageUrlUpdateFails = _zeroRows;
    await _open(tester, svc);
    await _pickImage(tester);
    await _save(tester);

    _notSaved();
    expect(
        find.text("Exercise saved, but the image couldn't be attached. "
            '$_support'),
        findsOneWidget);
    expect(find.textContaining('permission'), findsNothing);
    expect(
        reported.map((f) => f.origin), ['CreateExerciseScreen.saveImageUrl']);
    expect(reported.single.error, _zeroRows);
  });

  testWidgets('a failed video_variants write is not "Exercise Saved!"',
      (tester) async {
    final svc = _Svc()
      ..ownerId = null
      ..variantsUpdateFails = _rls;
    await _open(tester, svc, editing: 'ex-1', role: 'admin');
    await _save(tester);

    expect(svc.calls, contains('update:text'));
    _notSaved();
    expect(
        find.text("Exercise saved, but the videos couldn't be attached. "
            '$_support'),
        findsOneWidget);
    expect(find.textContaining('rls refused'), findsNothing);
    expect(reported.map((f) => f.origin),
        ['CreateExerciseScreen.saveVideoVariants']);
  });

  testWidgets('a failed syncRelations is not "Exercise Saved!"',
      (tester) async {
    final svc = _Svc()..syncFails = _rls;
    await _open(tester, svc);
    await _save(tester);

    _notSaved();
    expect(
        find.text("Exercise saved, but the muscle and equipment details "
            "couldn't be saved. $_support"),
        findsOneWidget);
    expect(
        reported.map((f) => f.origin), ['CreateExerciseScreen.syncRelations']);
    expect(reported.single.error, same(_rls));
  });

  testWidgets(
      'several failures make ONE message, and a step that failed without an '
      "error is never reported with an earlier step's error", (tester) async {
    final svc = _Svc()
      ..imageUploadFails = http.ClientException('offline')
      ..syncFailsSilently = true;
    await _open(tester, svc);
    await _pickImage(tester);
    await _save(tester);

    _notSaved();
    // Not the connection hint: the sync failure is not known to be one.
    expect(
        find.text("Exercise saved, but the image couldn't be uploaded and the "
            "muscle and equipment details couldn't be saved. $_support"),
        findsOneWidget);
    expect(reported.map((f) => f.origin), ['CreateExerciseScreen.uploadImage'],
        reason: 'syncRelations recorded nothing; the stale ClientException '
            'must not be reported again as its error');
  });

  group('media-only edit (coach on a library exercise)', () {
    testWidgets('the media write failing says nothing was saved',
        (tester) async {
      final svc = _Svc()..mediaRpcFails = _rls;
      await _open(tester, svc, editing: 'ex-1');
      expect(find.textContaining('This is a library exercise'), findsOneWidget);
      await _pickImage(tester);
      await _save(tester);

      expect(svc.calls, isNot(contains('update:text')));
      _notSaved();
      expect(
          find.text("Couldn't save the media — nothing was changed. $_support"),
          findsOneWidget);
      expect(find.textContaining('Exercise saved'), findsNothing);
      expect(reported.map((f) => f.origin),
          ['CreateExerciseScreen.updateExerciseMedia']);
    });

    testWidgets('a 0-row media write (no error) is still a failure',
        (tester) async {
      final svc = _Svc()..mediaRpcFailsSilently = true;
      await _open(tester, svc, editing: 'ex-1');
      await _save(tester);
      _notSaved();
      expect(
          find.text("Couldn't save the media — nothing was changed. $_support"),
          findsOneWidget);
    });

    testWidgets('an upload failing before a good media write is named',
        (tester) async {
      final svc = _Svc()..imageUploadFails = _storageDown;
      await _open(tester, svc, editing: 'ex-1');
      await _pickImage(tester);
      await _save(tester);
      _notSaved();
      expect(
          find.text("Couldn't save all the media — the image couldn't be "
              'uploaded. $_support'),
          findsOneWidget);
    });

    testWidgets('control: success is unchanged', (tester) async {
      final svc = _Svc();
      await _open(tester, svc, editing: 'ex-1');
      await _pickImage(tester);
      await _save(tester);
      expect(svc.calls, ['uploadImage', 'updateExerciseMedia']);
      expect(find.text(_saved), findsOneWidget);
      expect(reported, isEmpty);
    });
  });

  testWidgets('control: all steps succeeding is the unchanged success',
      (tester) async {
    final svc = _Svc();
    await _open(tester, svc);
    await _pickImage(tester);
    await _pickVideos(tester, 2);
    await _save(tester);

    expect(svc.calls, [
      'create',
      'uploadImage',
      'uploadVideo',
      'uploadVideo',
      'update:image_url',
      'update:video_variants',
      'syncRelations',
    ]);
    expect(find.text(_saved), findsOneWidget);
    expect(find.textContaining("couldn't"), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets(
      'retry: Save again after a failed upload re-uploads the kept pick and '
      'then succeeds', (tester) async {
    final svc = _Svc()..imageUploadFails = _storageDown;
    await _open(tester, svc);
    await _pickImage(tester);
    await _save(tester);
    _notSaved();

    svc.imageUploadFails = null;
    await _save(tester);
    expect(svc.calls.where((c) => c == 'uploadImage'), hasLength(2));
    expect(svc.calls.last, 'syncRelations');
    expect(svc.calls, contains('update:image_url'));
    expect(find.text(_saved), findsOneWidget);
  });

  group('CustomExerciseService.updateExerciseMedia (real service)', () {
    test('the RPC answering false (0 rows updated) is a failure', () async {
      final svc = CustomExerciseService()..lastError = 'stale';
      _body = 'false';
      expect(await svc.updateExerciseMedia('ex-1', videoVariants: const []),
          isFalse);
      expect(svc.lastError, isNotNull);
      expect(svc.lastError, isNot('stale'));
      expect(_requests.single.url.path, endsWith('/rpc/update_exercise_media'));
    });

    test('control: the RPC answering true is a success, lastError cleared',
        () async {
      final svc = CustomExerciseService()..lastError = 'stale';
      _body = 'true';
      expect(await svc.updateExerciseMedia('ex-1', videoVariants: const []),
          isTrue);
      expect(svc.lastError, isNull);
    });
  });
}
