import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';
import '../support/session_switch.dart';

// P0-FL-56a · Progress photos (Add Photo, and the three baseline slots).
//
// At f191d48 both picker calls were unguarded: a denied permission or missing
// camera was an uncaught async error and the control did nothing. An upload or
// insert failure said "Failed to upload photo" / "Upload failed." and recorded
// nothing; a baseline copy `remove` left behind (it does not throw) still said
// "Front photo updated"; and a failed reload after a stored photo replaced the
// whole screen with "Could not load your progress".
//
// HOW TO SEE IT FAIL: run against f191d48's progress_screen.dart.

const _uid = '00000000-0000-4000-8000-00000000056a';
const _uidB = '00000000-0000-4000-8000-00000000056b';

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);

  bool uploadFails = false;
  bool insertFails = false;
  bool readsFail = false;
  bool removeThrows = false;

  /// What a list of the member's folder answers after the cleanup.
  List<String> left = const [];
  final storage = <String>[];
  int inserts = 0;

  @override
  void reset() {
    super.reset();
    uploadFails = insertFails = readsFail = removeThrows = false;
    left = const [];
    storage.clear();
    inserts = 0;
    reads['user_profiles'] = {'weight_kg': 80.0, 'weight_goal_kg': 75.0};
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.startsWith('/storage/v1/object/sign/')) {
      return json({'statusCode': '404', 'error': 'not_found', 'message': 'no'},
          400, request);
    }
    if (path.startsWith('/storage/v1/object/list/')) {
      storage.add('LIST');
      return json([
        for (final n in left) {'name': n}
      ], 200, request);
    }
    if (path.startsWith('/storage/v1/object/')) {
      storage.add('${request.method} $path');
      if (request.method == 'DELETE') {
        return removeThrows
            ? json({'statusCode': '500', 'error': 'x', 'message': 'SECRET'},
                500, request)
            : json([], 200, request);
      }
      return uploadFails
          ? json({'statusCode': '403', 'error': 'x', 'message': 'SECRET'}, 403,
              request)
          : json({'Key': 'k'}, 200, request);
    }
    if (request.method == 'GET' && readsFail) {
      return json({'message': 'SECRET', 'code': 'XX000'}, 500, request);
    }
    if (request.method == 'POST' && path.endsWith('/progress_photo_logs')) {
      inserts++;
      if (insertFails) {
        return json({'message': 'SECRET', 'code': '42501'}, 403, request);
      }
    }
    return super.send(request);
  }

  http.StreamedResponse json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() async {
    await signInAs(_uid);
    server.reset();
    picker.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProgressScreen())));
    await settle(t);
    await t.tap(find.text('Photos'));
    await settle(t);
    expect(find.text('Start Photos'), findsOneWidget, reason: 'premise');
    expect(reported, isEmpty, reason: 'premise: a clean load');
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  Future<void> choose(WidgetTester t, String control,
      {String row = 'Choose from Gallery'}) async {
    await t.tap(find.text(control));
    await settle(t);
    await t.tap(find.text(row));
    await settle(t);
  }

  Future<void> waitFor(WidgetTester t, String text) => pumpUntil(
      t, () => find.text(text).evaluate().isNotEmpty,
      what: '"$text"', step: const Duration(milliseconds: 5));

  void nothingRaw() => expect(find.textContaining('SECRET'), findsNothing);

  for (final (control, origin) in [
    ('Add Photo', 'progress.photo'),
    ('Front', 'progress.baseline'),
  ]) {
    group('$control picker', () {
      testWidgets('photo access denied: says where to allow it, recorded',
          (t) async {
        await open(t);
        picker.fails('photo_access_denied');
        await choose(t, control);
        const msg = "Couldn't open your photos — allow photo access in "
            'Settings, then try again.';
        expect(find.text(msg), findsOneWidget,
            reason: 'THE defect: uncaught, and the control did nothing');
        expect(liveRegionOver(msg), findsWidgets);
        expect(origins(), ['$origin.pick.gallery']);
        expect(server.storage, isEmpty);
        nothingRaw();
        await close(t);
      });

      testWidgets('camera denied: the camera wording and origin', (t) async {
        await open(t);
        picker.fails('camera_access_denied');
        await choose(t, control, row: 'Take Photo');
        expect(
            find.text("Couldn't open your camera — allow camera access in "
                'Settings, then try again.'),
            findsOneWidget);
        expect(origins(), ['$origin.pick.camera']);
        await close(t);
      });

      testWidgets('any other picker failure: the generic next step; the next '
          'pick works', (t) async {
        await open(t);
        picker.fails('no_available_camera');
        await choose(t, control, row: 'Take Photo');
        expect(find.text("Couldn't open your camera — $tryAgainHint"),
            findsOneWidget);
        expect(origins(), ['$origin.pick.camera']);
        nothingRaw();
        picker.calls.clear();
        picker.cancels();
        await choose(t, control);
        expect(picker.calls, hasLength(1), reason: 'the guard was released');
        await close(t);
      });

      testWidgets('an unreadable pick: said, recorded, nothing uploaded',
          (t) async {
        await open(t);
        picker.picksUnreadable();
        await choose(t, control);
        await waitFor(t, "Couldn't use that photo — $tryAgainHint");
        expect(origins(), ['$origin.read']);
        expect(server.storage, isEmpty);
        expect(find.textContaining('vanished'), findsNothing);
        await close(t);
      });

      testWidgets('NEGATIVE CONTROL: cancelling the sheet or the picker is '
          'silent', (t) async {
        await open(t);
        picker.cancels();
        await choose(t, control);
        expect(picker.calls, ['pickImage:1']);
        await t.tap(find.text(control));
        await settle(t);
        await t.tapAt(const Offset(10, 10)); // dismiss the sheet
        await settle(t);
        expect(picker.calls, hasLength(1));
        expect(find.byType(SnackBar), findsNothing);
        expect(reported, isEmpty);
        expect(server.storage, isEmpty);
        await close(t);
      });

      testWidgets("A's pick, B signs in while the picker is open: nothing "
          "lands in B's folder, recorded", (t) async {
        await open(t);
        final gate = Completer<Object?>();
        picker.answer = (_) => gate.future;
        await choose(t, control);
        await t.runAsync(() => signInAs(_uidB));
        gate.complete(picker.photoPath);
        await pumpUntil(t, () => reported.isNotEmpty, what: 'the refusal');
        await settle(t);
        expect(origins(), ['$origin.identity']);
        expect(server.storage, isEmpty);
        expect(server.inserts, 0);
        await close(t);
      });

      testWidgets('a second tap while the picker is open opens nothing',
          (t) async {
        await open(t);
        final gate = Completer<Object?>();
        picker.answer = (_) => gate.future;
        await choose(t, control);
        expect(picker.calls, hasLength(1), reason: 'premise: it is open');
        await t.tap(find.text(control));
        await settle(t);
        expect(find.text('Choose from Gallery'), findsNothing,
            reason: 'no second source sheet, so no second picker');
        gate.complete(null);
        await settle(t);
        expect(picker.calls, hasLength(1));
        await close(t);
      });
    });
  }

  group('Add Photo, after the pick', () {
    testWidgets('a refused upload: said, recorded, no row written', (t) async {
      await open(t);
      server.uploadFails = true;
      await choose(t, 'Add Photo');
      await waitFor(t, "Couldn't save your photo — $tryAgainHint");
      expect(origins(), ['progress.photo.upload']);
      expect(server.inserts, 0);
      nothingRaw();
      await close(t);
    });

    testWidgets('a refused row: said, recorded under its own origin',
        (t) async {
      await open(t);
      server.insertFails = true;
      await choose(t, 'Add Photo');
      await waitFor(t, "Couldn't save your photo — $tryAgainHint");
      expect(server.inserts, 1);
      expect(origins(), ['progress.photo.save']);
      nothingRaw();
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: uploaded, logged, no notice', (t) async {
      await open(t);
      await choose(t, 'Add Photo');
      await pumpUntil(t, () => server.inserts == 1, what: 'the row');
      await settle(t);
      expect(server.storage.single, startsWith('POST /storage/v1/object/'
          'progress-photos/$_uid/gallery_'));
      expect(find.byType(SnackBar), findsNothing);
      expect(origins().where((o) => o.startsWith('progress.photo')), isEmpty);
      expect(find.text('Start Photos'), findsOneWidget);
      await close(t);
    });

    testWidgets('the refresh after a stored photo fails: the screen is kept, '
        'the refresh failure is said and recorded', (t) async {
      await open(t);
      server.readsFail = true;
      await choose(t, 'Add Photo');
      await waitFor(
          t,
          "Your photo is saved. Couldn't refresh your progress — "
          '$tryAgainHint');
      expect(find.text('Start Photos'), findsOneWidget,
          reason: 'what was shown is kept');
      expect(find.text('Could not load your progress'), findsNothing);
      expect(origins(), contains('ProgressScreen._loadData'));
      nothingRaw();
      await close(t);
    });
  });

  group('baseline, after the pick', () {
    testWidgets('a refused upload: said, recorded, nothing removed, never '
        '"updated"', (t) async {
      await open(t);
      server.uploadFails = true;
      await choose(t, 'Side');
      await waitFor(t, "Couldn't update your side photo — $tryAgainHint");
      expect(origins(), ['progress.baseline.upload']);
      expect(server.storage.where((s) => s.startsWith('DELETE')), isEmpty);
      expect(find.text('Side photo updated'), findsNothing);
      nothingRaw();
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: "updated"; remove answering [] with no '
        'other copy left is fine', (t) async {
      await open(t);
      server.left = ['front.png', 'side.jpg']; // the new one; another side's
      await choose(t, 'Front');
      await waitFor(t, 'Front photo updated');
      expect(server.storage.where((s) => s.startsWith('DELETE')), hasLength(1));
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('an earlier copy still there after remove: recorded and said, '
        'not "updated"', (t) async {
      await open(t);
      server.left = ['front.png', 'front.jpg'];
      await choose(t, 'Front');
      await waitFor(
          t,
          "Front photo saved. Couldn't remove the earlier one, so it may "
          'still show — $tryAgainHint');
      expect(find.text('Front photo updated'), findsNothing,
          reason: 'the stale copy is found first and still shows');
      expect(origins(), ['ProgressScreen._setBaselinePhoto.cleanup']);
      await close(t);
    });

    testWidgets('remove throws: recorded and said', (t) async {
      await open(t);
      server.removeThrows = true;
      await choose(t, 'Back');
      await waitFor(
          t,
          "Back photo saved. Couldn't remove the earlier one, so it may "
          'still show — $tryAgainHint');
      expect(origins(), ['ProgressScreen._setBaselinePhoto.cleanup']);
      nothingRaw();
      await close(t);
    });
  });

  testWidgets('NEGATIVE CONTROL: a failed FIRST load is still the load '
      'failure', (t) async {
    server.readsFail = true;
    await t.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProgressScreen())));
    await pumpUntil(t,
        () => find.text('Could not load your progress').evaluate().isNotEmpty,
        what: 'the load failure');
    expect(origins(), contains('ProgressScreen._loadData'));
    expect(find.byType(SnackBar), findsNothing);
    await close(t);
  });
}
