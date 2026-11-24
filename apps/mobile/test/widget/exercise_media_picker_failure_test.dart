import 'dart:async';
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
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-56a · Create/Edit Exercise › Media: the image and the video picker.
//
// At f191d48 both picks and both reads were unguarded (uncaught error, the
// tile did nothing); two taps opened two pickers; Save while a picked file was
// still being read stored the exercise WITHOUT it and said "Exercise Saved!";
// and the video landed on an index, so removing its entry during the read gave
// it to another entry or threw. (What follows — upload, attach, sync — is
// pinned by create_exercise_media_failures_test.)
//
// HOW TO SEE IT FAIL: run against f191d48's create_exercise_screen.dart.

const _uid = '00000000-0000-4000-8000-00000000e56a';

final _user = User(
  id: _uid,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-16T00:00:00Z',
);

class _Svc extends CustomExerciseService {
  final calls = <String>[];

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
    calls.add('create');
    return 'new-1';
  }

  @override
  Future<String?> uploadImage(Uint8List bytes, String ext, String id) async {
    calls.add('uploadImage');
    return 'https://cdn.test/image.$ext';
  }

  @override
  Future<String?> uploadVideo(
      Uint8List bytes, String ext, String id, String label) async {
    calls.add('uploadVideo:$ext');
    return 'https://cdn.test/video.$ext';
  }

  @override
  Future<bool> updateExercise(String id, Map<String, dynamic> updates) async =>
      true;
  @override
  Future<bool> syncRelations(String id, Map<String, dynamic> j) async => true;
}

/// A picked file whose read waits on [gate] (a large video).
class _SlowFile extends Fake implements XFile {
  final gate = Completer<Uint8List>();
  @override
  String get name => 'form.mp4';
  @override
  Future<Uint8List> readAsBytes() => gate.future;
}

class _SlowPicker extends ImagePicker {
  final file = _SlowFile();
  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async =>
      file;
}

void main() {
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];
  late _Svc svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSignedInSupabase(RowCheckingPostgrest(_uid));
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() {
    picker.reset();
    reported.clear();
    setFailureSink(reported.add);
    svc = _Svc();
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, {ImagePicker? media}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2600);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user),
        customExerciseSvcProvider.overrideWithValue(svc),
        currentUserProfileProvider
            .overrideWith((ref) async => {'id': _uid, 'role': 'coach'}),
        editingExerciseProvider.overrideWith((ref) => null),
        if (media != null) exerciseMediaPickerProvider.overrideWithValue(media),
      ],
      child: const MaterialApp(home: CreateExerciseScreen()),
    ));
    await settle(t);
    await t.enterText(
        find.widgetWithText(TextFormField, 'Exercise Name *'), 'Goblet Squat');
    await t.tap(find.text('MEDIA'));
    await settle(t);
  }

  Future<void> addEntry(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.add_circle_outline));
    await settle(t);
  }

  int images(WidgetTester t) => t
      .widgetList<Container>(find.byType(Container))
      .where((c) =>
          c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).image?.image is MemoryImage)
      .length;

  Future<void> pickReadableImage(WidgetTester t) async {
    await t.tap(find.text('Tap to add image'));
    await pumpUntil(t, () => images(t) == 1, what: 'the image preview');
  }

  Finder imageTile() => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).image?.image is MemoryImage);

  Future<void> waitFor(WidgetTester t, String text) => pumpUntil(
      t, () => find.text(text).evaluate().isNotEmpty,
      what: '"$text"', step: const Duration(milliseconds: 5));

  void nothingRaw() {
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('vanished'), findsNothing);
  }

  for (final (kind, library) in [('image', 'photos'), ('video', 'videos')]) {
    group('$kind picker', () {
      final method = kind == 'image' ? 'pickImage:1' : 'pickVideo:1';
      final tile = kind == 'image' ? 'Tap to add image' : 'Upload from device';

      Future<void> ready(WidgetTester t) async {
        await open(t);
        if (kind == 'video') await addEntry(t);
      }

      Future<void> tap(WidgetTester t) async {
        await t.tap(find.text(tile));
        await settle(t);
      }

      testWidgets('access denied: says where to allow it, recorded',
          (t) async {
        await ready(t);
        picker.fails('photo_access_denied');
        await tap(t);
        final msg = "Couldn't open your $library — allow photo access in "
            'Settings, then try again.';
        expect(find.text(msg), findsOneWidget,
            reason: 'THE defect: uncaught, and the tile did nothing');
        expect(liveRegionOver(msg), findsWidgets);
        expect(origins(), ['exercise.$kind.pick.gallery']);
        nothingRaw();
      });

      testWidgets('any other picker failure: the generic next step; the tile '
          'works again', (t) async {
        await ready(t);
        picker.fails('boom');
        await tap(t);
        expect(find.text("Couldn't open your $library — $tryAgainHint"),
            findsOneWidget);
        expect(origins(), ['exercise.$kind.pick.gallery']);
        nothingRaw();
        picker.cancels();
        await tap(t);
        expect(picker.calls, [method, method]);
      });

      testWidgets('an unreadable pick: said, recorded, nothing selected',
          (t) async {
        await ready(t);
        picker.picksUnreadable();
        await tap(t);
        await waitFor(t, "Couldn't use that $kind — $tryAgainHint");
        expect(origins(), ['exercise.$kind.read']);
        expect(find.text(tile), findsOneWidget);
        nothingRaw();
      });

      testWidgets('NEGATIVE CONTROL: cancelling is silent', (t) async {
        await ready(t);
        picker.cancels();
        await tap(t);
        expect(picker.calls, [method]);
        expect(find.byType(SnackBar), findsNothing);
        expect(reported, isEmpty);
      });

      testWidgets('a second tap while the picker is open opens no second one',
          (t) async {
        await ready(t);
        final gate = Completer<Object?>();
        picker.answer = (_) => gate.future;
        await tap(t);
        await tap(t);
        expect(picker.calls, hasLength(1));
        gate.complete(null);
        await settle(t);
      });
    });
  }

  testWidgets('an image already chosen is kept when the next pick fails, '
      'cannot be read, or is cancelled', (t) async {
    await open(t);
    await pickReadableImage(t);
    picker.fails('photo_access_denied');
    await t.tap(imageTile());
    await settle(t);
    expect(images(t), 1);
    picker.picksUnreadable();
    await t.tap(imageTile());
    await pumpUntil(t, () => origins().contains('exercise.image.read'),
        what: 'the read failure');
    expect(images(t), 1);
    picker.cancels();
    await t.tap(imageTile());
    await settle(t);
    expect(images(t), 1);
    expect(reported, hasLength(2));
  });

  testWidgets('POSITIVE CONTROL: picked image and video are uploaded and '
      'saved, no notice', (t) async {
    await open(t);
    await pickReadableImage(t);
    await addEntry(t);
    await t.tap(find.text('Upload from device'));
    await waitFor(t, 'Video selected');
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('Exercise Saved!'), findsOneWidget);
    expect(svc.calls, ['create', 'uploadImage', 'uploadVideo:png']);
    expect(find.byType(SnackBar), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets('Save waits while a picked file is being read, then saves it',
      (t) async {
    final media = _SlowPicker();
    await open(t, media: media);
    await addEntry(t);
    await t.tap(find.text('Upload from device'));
    await settle(t);
    await t.tap(find.text('Save'));
    await settle(t);
    expect(svc.calls, isEmpty,
        reason: 'THE defect: saved without the video, "Exercise Saved!"');
    expect(find.text('Exercise Saved!'), findsNothing);

    media.file.gate.complete(Uint8List.fromList([0, 0, 0, 1]));
    await settle(t);
    expect(find.text('Video selected'), findsOneWidget);
    await t.tap(find.text('Save'));
    await settle(t);
    expect(svc.calls, ['create', 'uploadVideo:mp4']);
    expect(find.text('Exercise Saved!'), findsOneWidget);
  });

  testWidgets('an entry removed while its video is read: no crash, and the '
      'other entry does not get the video', (t) async {
    final media = _SlowPicker();
    await open(t, media: media);
    await addEntry(t);
    await addEntry(t);
    await t.tap(find.text('Upload from device').first);
    await settle(t);
    await t.tap(find.byIcon(Icons.remove_circle_outline).first);
    await settle(t);
    media.file.gate.complete(Uint8List.fromList([0, 0, 0, 1]));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('Video selected'), findsNothing,
        reason: 'the video belonged to the removed entry');
    expect(find.text('Upload from device'), findsOneWidget);
    expect(reported, isEmpty);
  });
}
